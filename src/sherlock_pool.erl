-module(sherlock_pool).

%% API
-export([push_job_to_queue/1]).
-export([push_job_to_queue/2]).
-export([destroy/1]).
%% Internal API
-export([init/0]).
-export([create/2]).
-export([push_worker/2]).
-export([mx_size/1]).
-export([mn_size/1]).
-export([update_csize/2]).
-export([get_qid/1]).
-export([get_wid/1]).
-define(CTH, 1 bsl 64).

-define(DEFAULT_TTL, 5000).

-record(?MODULE,{
  name,
  c_size = 0,
  mx_size = 1,
  mn_size = 1,
  q_id = -1,
  w_id = -1,
  qt,
  wt,
  mfa = {s,w,[]}
}).

-record(sherlock_job,{
  q_id,
  ref,
  pid,
  ttl
}).

-record(sherlock_wrk,{
  w_id,
  pid
}).

-record(sherlock_msg, {ref, workerpid}).

ttl(infinity = I) -> I;
ttl(Int) when is_integer(Int) and (Int >= 0) -> erlang:system_time(millisecond) + Int.

cts() ->
  ttl(0).

init() ->
  Options = [named_table, set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #?MODULE.name}],
  ets:new(?MODULE, Options).

init_wt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_wrk.w_id}],
  ets:new(?MODULE, Options).

init_qt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_wrk.w_id}],
  ets:new(?MODULE, Options).

create(PoolName, PoolArgs) ->
  Record = #?MODULE{},
  MFA = maps:get(mfa, PoolArgs, Record#?MODULE.mfa),
  Min = maps:get(min_size, PoolArgs, Record#?MODULE.mn_size),
  Max = maps:get(max_size, PoolArgs, max(Record#?MODULE.mx_size, Min)),
  Pool = Record#?MODULE{
    name = PoolName,
    mfa = MFA,
    wt = init_wt(),
    qt = init_qt(),
    mx_size = Max,
    mn_size = Min
  },
  ets:insert_new(?MODULE, Pool).

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

w_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.wt).
q_tab(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.qt).

update_csize(PoolName, Csize) ->
  ets:update_element(?MODULE, PoolName, {#?MODULE.c_size, Csize}).

get_wid(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.w_id).

get_qid(PoolName) ->
  ets:lookup_element(?MODULE, PoolName, #?MODULE.q_id).

take_from_qt(Qtab, Id, WorkerPid) ->
  Cts = cts(),
  case ets:take(Qtab, Id) of
    [#sherlock_job{ttl = Sts}] when (Sts > Cts) ->
      retry;
    [#sherlock_job{ref = R, pid = Pid}] ->
      case is_process_alive(Pid) of
        true ->
%%          maybe monitor ???
          {ok, Pid, #sherlock_msg{ref = R, workerpid = WorkerPid}};
        false ->
          retry
      end;
    [] ->
      gone
  end.
take_from_wt(Wtab, Id) ->
  case ets:take(Wtab, Id) of
    [#sherlock_wrk{pid = WorkerPid}] ->
      {ok, WorkerPid};
    [] ->
      gone
  end.

push_wt(WTab, Id, WorkerPid) ->
  ets:insert(WTab, #sherlock_wrk{w_id = Id, pid = WorkerPid}).

push_worker(PoolName, WorkerPid) ->
  QTab = q_tab(PoolName),
  WTab = w_tab(PoolName),
  push_worker(PoolName, WorkerPid, QTab, WTab).

push_worker(PoolName, WorkerPid, QTab, WTab) ->
  NextId = worker_id_incr(PoolName),
  _ = push_wt(WTab, NextId, WorkerPid),
  case take_from_qt(QTab, NextId, WorkerPid) of
    {ok, Dest, Msg} ->
      case take_from_wt(WTab, NextId) of
        {ok, _} ->
          Dest ! Msg;
        gone -> ok
      end;
    retry ->
      take_from_wt(WTab, NextId),
      push_worker(PoolName, QTab, WTab, WorkerPid);
    gone ->
      ok
  end.

push_qt(QTab, NextId, Timeout, WaitingPid, Secret) ->
  ets:insert(QTab, #sherlock_job{q_id = NextId, ttl = ttl(Timeout), pid = WaitingPid, ref = Secret}).

push_job_to_queue(PoolName) ->
  push_job_to_queue(PoolName, ?DEFAULT_TTL).
push_job_to_queue(PoolName, Timeout) ->
  QTab = q_tab(PoolName),
  WTab = w_tab(PoolName),
  WaitingPid = self(),
  Secret = erlang:make_ref(),
  case push_job_to_queue(PoolName, Timeout, QTab, WTab, WaitingPid, Secret) of
    {ok, _WorkerPid} = Result->  Result;
    wait ->
      wait(Secret, Timeout)
  end.

push_job_to_queue(PoolName, Timeout, QTab, WTab, WaitingPid, Secret) ->
  NextId = queue_id_incr(PoolName),
  _ = push_qt(QTab, NextId, Timeout, WaitingPid, Secret),
  case take_from_wt(WTab, NextId) of
    {ok, WorkerPid} = Result ->
      case take_from_qt(QTab, NextId, WorkerPid) of
        {ok, _, _} -> Result;
        gone ->
          wait
      end;
    gone ->
      wait
  end.

wait(Secret, Timeout) ->
  receive
    #sherlock_msg{ref = Secret, workerpid = Worker} ->
      _ = wait(Secret, 0),
      {ok, Worker}
  after
    Timeout ->
      {timeout, Timeout}
  end.