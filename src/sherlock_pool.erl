-module(sherlock_pool).
-include("sherlock_defaults_h.hrl").

%% API
-export([new/2]).
-export([usage_decr/1]).
-export([usage_incr/1]).
-export([stop/1]).

-export([lease_worker/1]).
-export([lease_worker/2]).
-export([release_worker/2]).

%% INTERNAL API
-export(['_new_main_'/0]).
-export([get_queue/1]).
-export([get_standby/1]).
-export([get_size/1]).

-export([get_free_bind_id_idx/1]).
-export([free_bind_id_idx/2]).

-export([add_worker/3]).
-export([sub_worker/3]).


-define(WRK_FIFO, '0_wrk').
-define(JOB_FIFO, '1_job').
%%-define(WRK_FILO, '1_wrk').
%%-define(JOB_FILO, '2_job').
%%
%%-type worker() :: ?WRK_FIFO.
%%-type job()    :: ?JOB_FIFO.

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
  size = 1                            ,
  used = 0                            ,
  queue = nil                         ,
  standby = nil                       ,
  bind_id = -1                        ,
  indexes = 0
                                      }).

-record(order, {s1 = os:perf_counter(), s2 = erlang:make_ref(), binding = 0}).

-record(sherlock_queue, {
  order = #order{},
  ref,
  proc = self(),
  ttl = ?SHERLOCK_WAIT_UNTIL(?SHERLOCK_POOL_DEFAULT_TTL)
                        }).
-record(sherlock_standby,                       {
  idx,
  lut = ?SHERLOCK_WAIT_UNTIL(0),
  pid
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
  ets:new(?MODULE, [ordered_set, public, #write_concurrency{}, #read_concurrency{}, #keypos{idx = #sherlock_queue.order}]).


create_standby_tab() ->
  ets:new(?MODULE, [set, public, #write_concurrency{}, #read_concurrency{}, #keypos{idx = #sherlock_standby.idx}]).

new(Name, Opts) ->
  try get_size(Name),
    throw({?MODULE, {name_occupied, Name}})
  catch _What ->
    Default = #sherlock_pool{},
    Min = maps:get(size, Opts, Default#sherlock_pool.size),
    NewPoolRec = #sherlock_pool     {
    name = Name                     ,
    size = Min                      ,
    queue = create_queue_tab()      ,
    standby = create_standby_tab()
                                    },
    ets:insert_new(?MODULE, NewPoolRec)
  end.


stop(Name) ->
  ets:delete(?MODULE, Name).

usage_incr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.used, 1}).

usage_decr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#sherlock_pool.used, -1}).


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


lease_worker(Pool) ->
  lease_worker(Pool, ?SHERLOCK_POOL_DEFAULT_TTL).

lease_worker(Pool, Timeout) ->
  QTabRef = get_queue(Pool),
  BindId = get_next_bind_id(Pool),
  {QKey, Ref} = push_to_queue(QTabRef, BindId, Timeout),
  STabRef = get_standby(Pool),
  case is_worker_available(STabRef, BindId) of
    {true, WorkerPid} ->
      out_from_queue(QTabRef, QKey),
      WorkerPid;
    _ ->
      wait_for_worker(Ref, QKey, Timeout)
  end.


release_worker(Pool, WorkerPid) ->
  BindId = get_next_bind_id(Pool),
  QTabRef = get_queue(Pool),
  case take_next_job(QTabRef, BindId) of
    {Message, WaitingPid} ->
      WaitingPid ! Message#sherlock_msg{worker_pid = WorkerPid},
      ok;
    ran_out ->
      STabRef = get_standby(Pool),
      Standby = #sherlock_standby{idx = BindId, pid = WorkerPid},
      ets:insert_new(STabRef, Standby),
      {ok, ran_out}
  end.

get_next_bind_id(Pool) ->
  Threshold = get_size(Pool),
  ets:update_counter(?MODULE, Pool, {#sherlock_pool.bind_id, 1, Threshold-1, 0}).

push_to_queue(QTabRef, BindId, Timeout) ->
  Ref = erlang:make_ref(),
  Order = #order{binding = BindId},
  QueueEntry = #sherlock_queue{order = Order,ref = Ref, ttl = ?SHERLOCK_WAIT_UNTIL(Timeout)},
  ets:insert(QTabRef, QueueEntry),
  {Order, Ref}.

is_worker_available(STabRef, BindId) ->
  case ets:take(STabRef, BindId) of
    [#sherlock_standby{pid = WorkerPid}] -> {true, WorkerPid};
    _ -> {false, undefined}
  end.

out_from_queue(QTabRef, QKey) ->
  ets:delete(QTabRef, QKey).

wait_for_worker(Ref, QKey, Timeout) ->
  receive
    #sherlock_msg{ref = Ref, order = QKey, worker_pid = WorkerPid} ->
      WorkerPid
  after
    Timeout ->
      {?MODULE, {timeout, Timeout}}
  end.


take_next_job(QTabRef, BindId) ->
  First = ets:first(QTabRef),
  case do_take_next_job(QTabRef, BindId, First) of
    retry -> take_next_job(QTabRef, BindId);
    ran_out -> ran_out;
    Result -> Result
  end.

do_take_next_job(_QTabRef, _BindId, '$end_of_table') ->
  ran_out;
do_take_next_job(QTabRef, BindId, First) ->
  Result = try ets:next(QTabRef, First)
  catch _ ->
    retry
  end,
  case Result of
    #order{binding = BindId} = Key ->
      take_a_job(QTabRef, Key);
    #order{} = Key ->
      do_take_next_job(QTabRef, BindId, Key);
    retry -> retry;
    '$end_of_table' -> ran_out
  end.


take_a_job(QTabRef, Key) ->
  [#sherlock_queue{order = Order, ref = Ref, proc = WaitingPid}|_] = ets:take(QTabRef, Key),
  {#sherlock_msg{ref = Ref, order = Order}, WaitingPid}.

get_free_bind_id_idx(PoolName) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{indexes = Index, size = Size}|_] ->
      case do_get_free_index(Index, Size) of
        {ok, Slot, Counter} ->
          ets:update_element(?MODULE, PoolName, {#sherlock_pool.indexes, (Index bor Slot)}),
          Counter;
        {error, Error} ->
          throw({?MODULE, {Error, PoolName}})
      end;
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

free_bind_id_idx(PoolName, Binding) ->
  case ets:lookup(?MODULE, PoolName) of
    [#sherlock_pool{indexes = Index}|_] ->
      ets:update_element(?MODULE, PoolName, {#sherlock_pool.indexes, (Index bxor Binding)});
    _ -> throw({?MODULE, {undefined_pool, PoolName}})
  end.

do_get_free_index(Index, Size) ->
  io:format("Size ~p Index ~p~n", [Size, Index]),
  do_get_free_index(Index, Size, 0).

do_get_free_index(_Index, Size, Size) ->
  {error, has_no_empty_slot};
do_get_free_index(Index, Size, Counter) ->
 Slot = 1 bsl Counter,
 case Index band Slot of
   0 -> {ok, Slot, Counter};
   _ -> do_get_free_index(Index, Size, Counter+1)
 end.

add_worker(Name, Pid, BindID) ->
  STabRef = get_standby(Name),
  ets:insert_new(STabRef, #sherlock_standby{idx = BindID, pid = Pid}).

sub_worker(Name, Pid, Slot) ->
  STabRef = get_standby(Name),
  case ets:lookup(STabRef, Slot) of
    [#sherlock_standby{pid = Pid} = Obj|_] -> ets:delete_object(STabRef, Obj);
    _ -> ok
  end.