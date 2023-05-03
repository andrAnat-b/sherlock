-module(sherlock_pool).

-include("sherlock_defaults_h.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%% API
-export([push_job_to_queue/2]).
-export([fix_cfg/1]).
-export([get_info/1]).
-export([get_all_poolnames/0]).
%% Internal API
-export([replace_worker/3]).
-export([init/0]).
-export([create/2]).
-export([destroy/1]).


-export([mx_size/1]).
-export([mn_size/1]).
-export([get_qid/1]).
-export([get_wid/1]).

-export([occup/1]).
-export([occup/2]).
-export([free/1]).
-export([free/2]).
-export([get_occupied/1]).

-export([main_tab/1]).
-export([m_tab/1]).

-export([update_csize/2]).

-export([push_worker/3]).

-record(?MODULE, {
  name           ,
  c_size = 0     ,
  occupation = 0 ,
  mt             ,
  mx_size = 1    ,
  mn_size = 1    ,
  main           ,
  q_id = 1       ,
  w_id = 1       ,
  mfa = {sherlock_simple_worker, start_link,[0]}}).

-record(sherlock_job,{
  id,
  ref,
  pid,
  ttl,
  type
}).

-record(sherlock_msg, {ref, workerpid, monref}).

ttl(infinity = I) -> I;
ttl(Int) when is_integer(Int) and (Int >= 0) -> (erlang:system_time(millisecond) + Int) - 5.

cts() ->
  ttl(0).

init() ->
  Options = [named_table, set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #?MODULE.name}],
  ets:new(?MODULE, Options).

init_main() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, false}, {keypos, #sherlock_job.id}],
  ets:new(?MODULE, Options).

init_mt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}],
  ets:new(?MODULE, Options).

create(PoolName, PoolArgs) ->
  Record = #?MODULE{},
  MFA = maps:get(mfa, PoolArgs),
  Min = maps:get(min_size, PoolArgs),
  Max = maps:get(max_size, PoolArgs),
  Pool = Record#?MODULE{
    name = PoolName,
    mfa = MFA,
    main = init_main(),
    mt = init_mt(),
    mx_size = Max,
    mn_size = Min
  },
  ets:insert(?MODULE, Pool).

destroy(PoolName) ->
  ets:delete(?MODULE, PoolName).

mx_size(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mx_size).

mn_size(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mn_size).

worker_id_incr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#?MODULE.w_id, 1, ?CTH, 0}).

queue_id_incr(PoolName) ->
  ets:update_counter(?MODULE, PoolName, {#?MODULE.q_id, 1, ?CTH, 0}).

main_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.main).

m_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mt).

update_csize(PoolName, Csize) ->
  ets:update_element(?MODULE, PoolName, {#?MODULE.c_size, Csize}).

get_wid(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.w_id).

get_qid(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.q_id).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


push_worker(PoolName, WorkerPid, Type) ->
  Main = sherlock_config:main_tab(PoolName),
  push_worker(PoolName, WorkerPid, Main, Type).

push_worker(PoolName, WorkerPid, Main, Type) ->
  free(PoolName),
  NextId = worker_id_incr(PoolName),
  Worker = #sherlock_job{
    id = NextId,
    type = wrk,
    ref = null,
    pid = WorkerPid,
    ttl = null
  },
  case ets:insert_new(Main, Worker) of
    false ->
      CTS = cts(),
      case ets:take(Main, NextId) of
        [#sherlock_job{ttl = TTL, type = job, ref = R, pid = P}] when (is_integer(TTL) and (TTL < CTS)) or (TTL == infinity) ->
          case Type of
            call ->
              MRef = sherlock_mon_wrkr:monitor_it(PoolName, P, WorkerPid),
              {P, MRef, #sherlock_msg{ref = R, monref = MRef, workerpid = WorkerPid}};
            _ ->
              MRef = erlang:monitor(process, P),
              {P, MRef, #sherlock_msg{ref = R, monref = MRef, workerpid = WorkerPid}}
          end;
        _ ->
          push_worker(PoolName, WorkerPid, Main, Type)
      end;
    true -> ok
  end.


push_job_to_queue(PoolName, Timeout) ->
  occup(PoolName),
  Main = sherlock_config:main_tab(PoolName),
  WaitingPid = self(),
  Secret = erlang:make_ref(),
  case push_job_to_queue(PoolName, Timeout, Main, WaitingPid, Secret) of
    {ok, _WorkerPid, _MonRef} = Result->
      Result;
    {wait, _Object} ->
      Fun = fun () ->
%%        ets:delete_object(Main, Object),
%%        free(PoolName),
            ok
      end,
      wait(Secret, Timeout+5, Fun)
  end.

push_job_to_queue(PoolName, Timeout, Main, WaitingPid, Secret) ->
  NextId = queue_id_incr(PoolName),
  Job =
    #sherlock_job{
      id = NextId,
      ttl = ttl(Timeout),
      pid = WaitingPid,
      ref = Secret,
      type = job
    },
  case ets:insert_new(Main, Job) of
    true ->
      {wait, Job};
    _ ->
      [#sherlock_job{pid = WorkerPid, type = wrk}] = ets:take(Main, NextId),
      MonRef = sherlock_mon_wrkr:monitor_me(PoolName, WorkerPid),
      {ok, WorkerPid, MonRef}
  end.

wait(Secret, Timeout, Fun) ->
  receive
    #sherlock_msg{ref = Secret, workerpid = Worker, monref = MonRef} ->
      {ok, Worker, MonRef}
  after
    Timeout ->
      Fun(),
      {timeout, Timeout}
  end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fix_cfg(Opts) ->
  D = #?MODULE{},
  MFA = maps:get(mfa, Opts, D#?MODULE.mfa),
  Min = maps:get(min_size, Opts, D#?MODULE.mn_size),
  Max = maps:get(max_size, Opts, max(D#?MODULE.mx_size, Min)),
  #{
    min_size => Min,
    max_size => Max,
    mfa => MFA
  }.

occup(Name) ->
  occup(Name, 1).

occup(Name, N) ->
  ets:update_counter(?MODULE, Name, {#?MODULE.occupation, N}).

free(Name) ->
  free(Name, 1).

free(Name, N) ->
  ets:update_counter(?MODULE, Name, {#?MODULE.occupation, N*(-1)}).

get_occupied(Name) ->
  ets:lookup_element(?MODULE, Name, #?MODULE.occupation).

replace_worker(PoolName, OldWorker, NewWorker) ->
  WTab = main_tab(PoolName),
  MatchSpecReplace = ets:fun2ms(fun
                           (#sherlock_job{id = JobID, pid = Worker, type = wrk, ref = null, ttl = null}) when Worker == OldWorker ->
                             #sherlock_job{id = JobID, pid = NewWorker, type = wrk, ref = null, ttl = null}
                         end),
  Success = (1 =:= ets:select_replace(WTab, MatchSpecReplace)),
  Success.

get_info(Poolname) ->
  case ets:lookup(?MODULE, Poolname) of
    [#?MODULE{} = R|_] ->
      #{
        name     => R#?MODULE.name,
        size     => R#?MODULE.c_size,
        usage    => R#?MODULE.occupation + R#?MODULE.mn_size,
        min_size => R#?MODULE.mn_size,
        max_size => R#?MODULE.mx_size
      };
    [] ->
      {error, undefined}
  end.

get_all_poolnames() ->
  Spec = ets:fun2ms(fun(#?MODULE{name = Name}) -> Name end),
  ets:select(?MODULE, Spec).