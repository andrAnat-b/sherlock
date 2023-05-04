-module(sherlock_pool).
-include("sherlock_defaults_h.hrl").

%% API
-export([new/2]).
-export([stop/1]).

-export([lease_worker/1]).
-export([lease_worker/2]).
-export([release_worker/2]).

%% INTERNAL API
-export(['_new_main_'/0]).
-export([get_pool_opts/1]).
-export([get_size/1]).
-export([get_max_size/1]).
-export([get_min_size/1]).
-export([get_queue/1]).
-export([get_standby/1]).
-export([usage_decr/1]).
-export([usage_incr/1]).
-export([usage_get/1]).
-export([jdiff/1]).

-export([worker_return/2]).

-export([join_pool/2]).
-export([leave_pool/2]).


-define(COUNTER_RESOLUTION, 64).
-define(COUNTER_TRESHOLD, 1 bsl ?COUNTER_RESOLUTION).

-record(read_concurrency,  {bool = true}).
-record(write_concurrency, {bool = true}).
-record(keypos, {idx = 1}).

-record(sherlock_msg, {
  ref,
  order,
  worker_pid
                      }).



-record(sherlock_pool,                {
  name = default                      ,
  size = 0                            ,
  min_size = 1                        ,
  max_size = 1                        ,
  used = 0                            ,
  queue = nil                         ,
  standby = nil                       ,
  stb_id = -1                         ,
  que_id = -1,
  pool_args = [],
  pool_mod,
  pool_fun
                                      }).


-record(sherlock_queue, {
  order,
  ref,
  proc = self(),
  ttl = ?SHERLOCK_WAIT_UNTIL(?SHERLOCK_POOL_DEFAULT_TTL)
                        }).



-record(sherlock_standby,{
  idx,
  pid,
  lut = ?SHERLOCK_WAIT_UNTIL(0)
}).

'_new_main_'() ->
  Opts = [
    public,
    set,
    named_table,
    #read_concurrency{},
    #write_concurrency{},
    #keypos{idx = #sherlock_pool.name}
  ],
  ets:new(?MODULE, Opts).

create_queue_tab() ->
  ets:new(?MODULE, [set, public, #write_concurrency{}, #read_concurrency{}, #keypos{idx = #sherlock_queue.order}]).

create_standby_tab() ->
  ets:new(?MODULE, [set, public, #write_concurrency{}, #read_concurrency{}, #keypos{idx = #sherlock_standby.idx}]).

get_queue(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{queue = QTRef}|_] -> QTRef;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

get_standby(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{standby = STRef}|_] -> STRef;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

get_size(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{size = Size}|_] -> Size;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

get_min_size(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{min_size = Size}|_] -> Size;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

get_max_size(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{max_size = Size}|_] -> Size;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.


usage_get(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{used = Size}|_] -> Size;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

usage_incr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.used, 1}).

usage_decr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.used, -1, 0, 0}).


next_queue_id(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.que_id, 1, ?COUNTER_TRESHOLD, 0}).

next_worker_id(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.stb_id, 1, ?COUNTER_TRESHOLD, 0}).

store_job(PoolName, WaitingPid, Ref, TTL) ->
  Id = next_queue_id(PoolName),
  QueTabRef = get_queue(PoolName),
  TimeToLive = calc_ttl(TTL),
  ets:insert(QueTabRef, #sherlock_queue{order = Id, ref = Ref, proc = WaitingPid, ttl = TimeToLive}),
  Id.

calc_ttl(infinity) ->
  infinity;
calc_ttl(TTL) when is_integer(TTL) and (TTL >= 0) ->
  ?SHERLOCK_WAIT_UNTIL(TTL).

take_job(PoolName, JobID) ->
  CurrentTime = erlang:system_time(millisecond),
  QueTabRef = get_queue(PoolName),
  case ets:take(QueTabRef, JobID) of
    [#sherlock_queue{ttl = StoredTime}|_] when is_integer(StoredTime) and (CurrentTime > StoredTime) -> pass;
    [#sherlock_queue{} = Job|_] -> Job;
    [] -> pass
  end.

worker_return(PoolName, WorkerPid) ->
  usage_decr(PoolName),
  Id = next_worker_id(PoolName),
  StbTabRef = get_standby(PoolName),
  ets:insert(StbTabRef, #sherlock_standby{idx = Id, pid = WorkerPid}),
  Id.

take_worker(PoolName, JobID) ->
  StbTabRef = get_standby(PoolName),
  case ets:take(StbTabRef, JobID) of
    [#sherlock_standby{pid = WorkerPid}|_] -> {ok, WorkerPid};
    [] -> pass
  end.

resize_pool(PoolName, Q) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.size, Q}).

join_pool(PoolName, WorkerPid) ->
  MaxSize = get_max_size(PoolName),
  NewSize = resize_pool(PoolName, 1),
  case NewSize =< MaxSize of
    true ->
      release_worker(PoolName, WorkerPid);
    _ ->
      resize_pool(PoolName, -1),
      leave_pool(PoolName, WorkerPid),
      {pool, oversize}
  end.

leave_pool(PoolName, WorkerPid) ->
  MinSize = get_min_size(PoolName),
  NewSize = resize_pool(PoolName, -1),
  case NewSize >= MinSize of
    true ->
      WorkerPid;
    _ ->
      resize_pool(PoolName, 1),
      worker_return(PoolName, WorkerPid),
      {pool, undersize}
  end.

wait_for_enqueued(Ref, JobId, Timeout) ->
  receive
    #sherlock_msg{ref = Ref, order = JobId, worker_pid = WorkerPid} ->
      erlang:link(WorkerPid),
      {ok, WorkerPid}
  after
    Timeout ->
      timed_out
  end.


get_pool_opts(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{} = Opts|_] ->
      #{
        worker_args => Opts#sherlock_pool.pool_args,
        mod => Opts#sherlock_pool.pool_mod,
        size => Opts#sherlock_pool.size,
        min_size => Opts#sherlock_pool.min_size,
        max_size => Opts#sherlock_pool.max_size,
        fn => Opts#sherlock_pool.pool_fun
      };
    [] -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

jdiff(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{stb_id = Standby, que_id = Queue}|_] -> Queue - Standby;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

%% =========================================================================

new(Name, Opts) ->
  try get_size(Name),
    throw({?MODULE, {name_occupied, Name}})
  catch _What ->
    Default = #sherlock_pool{},
    Min = maps:get(min_size, Opts, Default#sherlock_pool.min_size),
    Max = maps:get(max_size, Opts, erlang:max(Min, Default#sherlock_pool.max_size)),
    Module     = maps:get(mod, Opts, sherlock_uniworker),
    Function   = maps:get(fn,  Opts, start_link),
    NewPoolRec = #sherlock_pool{
      name = Name,
      min_size = Min,
      max_size = Max,
      queue = create_queue_tab(),
      standby = create_standby_tab(),
      pool_mod = Module,
      pool_fun = Function,
      pool_args = maps:get(worker_args, Opts, [#{state => 0}])
    },
    ets:insert_new(?MODULE, NewPoolRec)
  end.

stop(Name) ->
  ets:delete(?MODULE, Name).


lease_worker(PoolName) ->
  lease_worker(PoolName, ?SHERLOCK_POOL_DEFAULT_TTL).

lease_worker(PoolName, Timeout) ->
  usage_incr(PoolName),
  Ref = erlang:make_ref(),
  JobId = store_job(PoolName, self(), Ref, Timeout),
  case take_worker(PoolName, JobId) of
    {ok, WorkerPid} ->
      case take_job(PoolName, JobId) of
        #sherlock_queue{} ->
          erlang:link(WorkerPid),
          WorkerPid;
        _ ->
          wait_for_enqueued(Ref, JobId, Timeout)
      end;
    pass ->
      case wait_for_enqueued(Ref, JobId, Timeout) of
        {ok, WorkerPid} ->
          WorkerPid;
        timed_out ->
          {timeout, Timeout}
      end
  end.


release_worker(PoolName, WorkerPid) ->
  erlang:unlink(WorkerPid),
  JobId = worker_return(PoolName, WorkerPid),
  case take_job(PoolName, JobId) of
    #sherlock_queue{ref = Ref, proc = WaitingPid} ->
      case take_worker(PoolName, JobId) of
        {ok, WorkerPid} ->
          case is_process_alive(WaitingPid) of
            true ->
              erlang:send(WaitingPid, #sherlock_msg{order = JobId, ref = Ref, worker_pid = WorkerPid}),
              case is_process_alive(WaitingPid) of
                true -> ok;
                _ -> release_worker(PoolName, WorkerPid)
              end;
            _ ->
              release_worker(PoolName, WorkerPid)
          end;
        _ ->
          ok
      end;
    _ -> ok
  end.
