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

-export([set_mt/2]).

-export([mx_size/1]).
-export([mn_size/1]).
-export([c_size/1]).
%%-export([get_qid/1]).
%%-export([get_wid/1]).

-export([occup/1]).
-export([occup/2]).
-export([free/1]).
-export([free/2]).
-export([get_occupied/1]).

-export([q_tab/1]).
-export([w_tab/1]).
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
%%  q_id = 1       ,
  q_tab          ,
%%  w_id = 1       ,
  w_tab          ,
  mfa = {sherlock_simple_worker, start_link,[0]}}).

-record(sherlock_job,{
  id,
  ref = null,
  pid,
  ttl = null
}).

-record(sherlock_msg, {ref, workerpid, monref}).

ttl(infinity = I) -> I;
ttl(Int) when is_integer(Int) and (Int >= 0) -> (erlang:system_time(millisecond) + Int) - ?GAP.

cts() ->
  ttl(?GAP).

init() ->
  Options = [named_table, set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #?MODULE.name}],
  ets:new(?MODULE, Options).

init_q_tab() ->
  Options = [ordered_set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_job.id}],
  ets:new(?MODULE, Options).
init_w_tab() ->
  Options = [ordered_set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_job.id}],
  ets:new(?MODULE, Options).

init_mt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}],
  ets:new(?MODULE, Options).

create(PoolName, PoolArgs) ->
  Record = #?MODULE{},
  MFA = maps:get(mfa, PoolArgs),
  Min = maps:get(min_size, PoolArgs),
  Max = maps:get(max_size, PoolArgs),
  Pool = Record#?MODULE   {
    name    = PoolName    ,
    mfa     = MFA         ,
    q_tab   = init_q_tab(),
    w_tab   = init_w_tab(),
    mt      = init_mt()   ,
    mx_size = Max         ,
    mn_size = Min
                          },
  ets:insert(?MODULE, Pool).

destroy(PoolName) ->
  ets:delete(?MODULE, PoolName).

mx_size(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mx_size).

mn_size(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mn_size).

 c_size(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.c_size).

%%worker_id_incr(PoolName) ->
%%  [Next, _] = ets:update_counter(?MODULE, PoolName, [{#?MODULE.w_id, 1, ?CTH, 0}, {#?MODULE.occupation, -1}]),
%%  Next.
%%
%%queue_id_incr(PoolName) ->
%%  [Next, _] = ets:update_counter(?MODULE, PoolName, [{#?MODULE.q_id, 1, ?CTH, 0}, {#?MODULE.occupation, 1}]),
%%  Next.

q_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.q_tab).
w_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.w_tab).

m_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.mt).

update_csize(PoolName, Csize) ->
  ets:update_element(?MODULE, PoolName, {#?MODULE.c_size, Csize}).

%%get_wid(PoolName) ->
%%  ets:update_counter(?MODULE, PoolName, {#?MODULE.w_id, 0}).
%%
%%get_qid(PoolName) ->
%%  ets:update_counter(?MODULE, PoolName, {#?MODULE.q_id, 0}).

set_mt(PoolName, TabRef) ->
  ets:update_element(?MODULE, PoolName, {#?MODULE.mt, TabRef}).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


push_worker(PoolName, WorkerPid, Type) ->
  QueueT = sherlock_config:q_tab(PoolName),
  WorkrT = sherlock_config:w_tab(PoolName),
  push_worker(PoolName, WorkerPid, QueueT, WorkrT, Type).

push_worker(PoolName, WorkerPid, QueueT, WorkrT, Type) ->
  free(PoolName),
  CTS = cts(),
  case ets:take(QueueT, ets:first(QueueT)) of
    [] ->
      ets:insert(WorkrT, #sherlock_job{pid = WorkerPid, id = os:perf_counter()}),
      ok;
    [#sherlock_job{ttl = Ttl}= R] when (is_integer(Ttl) and (Ttl > CTS)) or Ttl == infinity ->
      Caller = R#sherlock_job.pid,
      MRef = monitor_ref(PoolName, Caller, WorkerPid, Type),
      {Caller, MRef, #sherlock_msg{ref = R#sherlock_job.ref, monref = MRef, workerpid = WorkerPid}};
    _ ->
      push_worker(PoolName, WorkerPid, QueueT, WorkrT, Type)
  end.


push_job_to_queue(PoolName, Timeout) ->
  QueueT = sherlock_config:q_tab(PoolName),
  WorkrT = sherlock_config:w_tab(PoolName),
  Caller = self(),
  Secret = erlang:make_ref(),
  Job = #sherlock_job{
    ttl = ttl(Timeout),
    pid = Caller,
    ref = Secret
                     },
  case push_job_to_queue(PoolName, Job, QueueT, WorkrT) of
    {ok, _WorkerPid, _MonRef} = Result->
      Result;
    {wait, Job, NextId} ->
      Fun = fun () ->
        ets:delete(QueueT, NextId),
        free(PoolName)
      end,
      wait(Secret, Timeout+?GAP, Fun)
  end.

push_job_to_queue(PoolName, Job, QueueT, WorkrT) ->
  occup(PoolName),
  case ets:take(WorkrT, ets:first(WorkrT)) of
    [] ->
      NextId = os:perf_counter(),
      ets:insert(QueueT, Job#sherlock_job{id = NextId}),
      {wait, Job, NextId};
    [#sherlock_job{pid = WorkerPid}] ->
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
  WTab = w_tab(PoolName),
  MatchSpecReplace = ets:fun2ms(fun
                           (#sherlock_job{id = JobID, pid = Worker}) when Worker == OldWorker ->
                             #sherlock_job{id = JobID, pid = NewWorker}
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

monitor_ref(PoolName, Caller, WorkerPid, call) ->
  sherlock_mon_wrkr:monitor_it(PoolName, Caller, WorkerPid);
monitor_ref(_, Caller, _, _) ->
  erlang:monitor(process, Caller).
