-module(sherlock_pool).

-include("sherlock_defaults_h.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%% API
-export([push_job_to_queue/2]).
-export([fix_cfg/1]).
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

-export([update_csize/2]).

-export([push_worker/3]).

-export([get_info/1]).

-export([get_all_poolnames/0]).

-record(?MODULE, {
  name           ,
  c_size = 0     ,
  occupation = 0 ,
  mx_size = 1    ,
  mn_size = 1    ,
  qt             ,
  q_id = 1       ,
  wt             ,
  w_id = 1       ,
  mfa = {sherlock_simple_worker, start_link,[0]}
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

-record(sherlock_msg, {ref, workerpid, monref}).

ttl(infinity = I) -> I;
ttl(Int) when is_integer(Int) and (Int >= 0) -> (erlang:system_time(millisecond) + Int) - 5.

cts() ->
  ttl(0).

init() ->
  Options = [named_table, set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #?MODULE.name}],
  ets:new(?MODULE, Options).

init_wt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_wrk.w_id}],
  ets:new(?MODULE, Options).

init_qt() ->
  Options = [set, public, {read_concurrency, true}, {write_concurrency, true}, {keypos, #sherlock_job.q_id}],
  ets:new(?MODULE, Options).

create(PoolName, PoolArgs) ->
  Record = #?MODULE{},
  MFA = maps:get(mfa, PoolArgs),
  Min = maps:get(min_size, PoolArgs),
  Max = maps:get(max_size, PoolArgs),
  Pool = Record#?MODULE{
    name = PoolName,
    mfa = MFA,
    wt = init_wt(),
    qt = init_qt(),
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
  TakeQt = ets:take(Qtab, Id),
  case TakeQt of
    [#sherlock_job{ttl = Sts}] when (Sts < Cts) and (Sts =/= infinity) ->
      retry;
    [#sherlock_job{ref = R, pid = Pid}] ->
      case is_process_alive(Pid) of
        true ->
          {ok, Pid, #sherlock_msg{ref = R, workerpid = WorkerPid}};
        false ->
          retry
      end;
    [] ->
      gone
  end.

take_from_wt(Wtab, Id) ->
  TakeWt = ets:take(Wtab, Id),
  case TakeWt of
    [#sherlock_wrk{pid = WorkerPid}] ->
      {ok, WorkerPid};
    [] ->
      gone
  end.

push_wt(WTab, Id, WorkerPid) ->
  ets:insert_new(WTab, #sherlock_wrk{w_id = Id, pid = WorkerPid}).



push_worker(PoolName, WorkerPid, Type) ->
  QTab = q_tab(PoolName),
  WTab = w_tab(PoolName),
  push_worker(PoolName, WorkerPid, QTab, WTab, Type).

push_worker(PoolName, WorkerPid, QTab, WTab, Type) ->
  free(PoolName),
  NextId = worker_id_incr(PoolName),
  true = push_wt(WTab, NextId, WorkerPid),
  case take_from_qt(QTab, NextId, WorkerPid) of
    {ok, Dest, Msg} ->
      case take_from_wt(WTab, NextId) of
        {ok, _} ->
          MonitorRef = case Type of
            call ->
              sherlock_mon_wrkr:monitor_it(PoolName, Dest, WorkerPid);
            _ ->
              erlang:monitor(process, Dest)
          end,
          NewMSG = Msg#sherlock_msg{monref = MonitorRef},
          Dest ! NewMSG,
          {Dest, NewMSG#sherlock_msg.monref};
        gone ->
          ok
      end;
    retry ->
      take_from_wt(WTab, NextId),
      push_worker(PoolName, WorkerPid, QTab, WTab, Type);
    gone ->
      ok
  end.

push_qt(QTab, NextId, Timeout, WaitingPid, Secret) ->
  ets:insert_new(QTab, #sherlock_job{q_id = NextId, ttl = ttl(Timeout), pid = WaitingPid, ref = Secret}).

push_job_to_queue(PoolName, Timeout) ->
  occup(PoolName),
  QTab = q_tab(PoolName),
  WTab = w_tab(PoolName),
  WaitingPid = self(),
  Secret = erlang:make_ref(),
  case push_job_to_queue(PoolName, Timeout, QTab, WTab, WaitingPid, Secret) of
    {ok, _WorkerPid} = Result->
      Result;
    wait ->
      wait(Secret, Timeout+5)
  end.

push_job_to_queue(PoolName, Timeout, QTab, WTab, WaitingPid, Secret) ->
  NextId = queue_id_incr(PoolName),
  true = push_qt(QTab, NextId, Timeout, WaitingPid, Secret),
  case take_from_wt(WTab, NextId) of
    {ok, WorkerPid} = Result ->
      TakeQt = take_from_qt(QTab, NextId, WorkerPid),
      case TakeQt of
        {ok, _, _} ->
          sherlock_mon_wrkr:monitor_me(PoolName, WorkerPid),
          Result;
        retry ->
          wait;
        gone ->
          wait
      end;
    gone ->
      wait
  end.

wait(Secret, Timeout) ->
  receive
    #sherlock_msg{ref = Secret, workerpid = Worker, monref = MonRef} ->
      {ok, Worker, MonRef}
  after
    Timeout ->
      {timeout, Timeout}
  end.

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
  WTab = get_wid(PoolName),
  MatchSpecReplace = ets:fun2ms(fun
                           (#sherlock_wrk{w_id = JobID, pid = Worker}) when Worker == OldWorker ->
                             #sherlock_wrk{w_id = JobID, pid = NewWorker}
                         end),
  Success = (1 =:= ets:select_replace(WTab, MatchSpecReplace)),
  if
    Success ->
      MatchSpec = ets:fun2ms(fun
                              (#sherlock_wrk{w_id = JobID, pid = Worker}) when Worker == OldWorker ->
                                JobID
                            end),
      case ets:select(WTab, MatchSpec) of
        [] -> ok;
        [JobID] ->
          QTab = get_wid(PoolName),
          TakeQt = take_from_qt(QTab, JobID, NewWorker),
          case TakeQt of
            {ok, WaitingPid, Message} ->
             case erlang:is_process_alive(WaitingPid) of
               true ->
                 WaitingPid ! Message;
               _ ->
                 push_worker(PoolName, NewWorker, call)
             end;
            retry ->
              push_worker(PoolName, NewWorker, call);
            gone ->
              push_worker(PoolName, NewWorker, call)
          end
      end;
    true ->
      MatchSpecDelete = ets:fun2ms(fun
                                      (#sherlock_wrk{w_id = _, pid = Worker}) when Worker == OldWorker ->
                                        true
                                    end),
      ets:select_delete(WTab, MatchSpecDelete),
      push_worker(PoolName, NewWorker, call)
  end.

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