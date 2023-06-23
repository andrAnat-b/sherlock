-module(sherlock).

-include("sherlock_defaults_h.hrl").

-export([start_pool/2]).
-export([stop_pool/1]).

-export([checkout/1]).
-export([checkout/2]).
-export([checkin/2]).

-export([transaction/2]).
-export([transaction/3]).

-export([start_balancer/2]).

-export([get_pool_metrics/0]).
-export([get_pool_info/1]).

-export([call_all_in_pool/2]).

-export(['_app_name_'/0]).

-export([start/0]).

start()->
  application:ensure_all_started(?MODULE).

%% API
start_pool(Name, Opts) ->
  case ?MODULE:get_pool_info(Name) of
    {error, undefined} ->
      StartPoolRes = sherlock_sentry_super_sup:start_child(Name, sherlock_pool:fix_cfg(Opts)),
%%      sherlock_meta:reconfig(),
      StartPoolRes;
    _ ->
      {error, {?MODULE, {pool_already_started, Name}}}
  end.

stop_pool(Name) ->
  StopPoolRes = sherlock_sentry_super_sup:stop_child(Name),
%%  sherlock_meta:reconfig(),
  StopPoolRes.



checkout(Name) ->
  checkout(Name, ?DEFAULT_TTL).

checkout(Name, Timeout) ->
  case sherlock_pool:push_job_to_queue(Name, Timeout) of
    {ok, _WorkerPid, _MonRef} = Ok ->
      Ok;
    Reason ->
      {error, {Name, Reason}}
  end.



checkin(PoolName, {WorkerPid, Ref}) when is_pid(WorkerPid) ->
  sherlock_mon_wrkr:demonitor_me(PoolName, WorkerPid, Ref).



transaction(Name, Fun) when is_function(Fun, 1) ->
  case checkout(Name) of
    {ok, Pid, Refer} ->
      Result = Fun(Pid),
      checkin(Name, {Pid, Refer}),
      Result;
    {error, _} = Error ->
      Error
  end.

transaction(Name, Fun, Timeout) when is_function(Fun, 1) ->
  case checkout(Name, Timeout) of
    {ok, Pid, Refer} ->
      Result = Fun(Pid),
      checkin(Name, {Pid, Refer}),
      Result;
    {error, _} = Error ->
      Error
  end.



'_app_name_'() ->
  ?MODULE.

get_pool_metrics() ->
  Names = sherlock_pool:get_all_poolnames(),
  [{Name, ?MODULE:get_pool_info(Name)}||Name<-Names].

get_pool_info(Poolname) ->
  sherlock_pool:get_info(Poolname).

start_balancer(Name, Opts) ->
  erlang:error(not_implemented).

call_all_in_pool(PoolName, CommandFun) ->
  case sherlock_pool_holder:get_all_workers(PoolName) of
    [_|_] = List ->
      [CommandFun(WPid) || WPid <- List];
    Error ->
      {error, Error}
  end.