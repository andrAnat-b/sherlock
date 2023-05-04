-module(sherlock).

-include("sherlock_defaults_h.hrl").

-export([start_pool/2]).
-export([stop_pool/1]).

-export([checkout/1]).
-export([checkout/2]).
-export([checkin/2]).

-export([transaction/2]).
-export([transaction/3]).

-export([get_pool_metrics/0]).

-export(['_app_name_'/0]).

-export([start/0]).

start()->
  application:ensure_all_started(?MODULE).

%% API
start_pool(Name, Opts) ->
  sherlock_sentry_super_sup:start_child(Name, sherlock_pool:fix_cfg(Opts)).

stop_pool(Name) ->
  sherlock_sentry_super_sup:stop_child(Name).



checkout(Name) ->
  checkout(Name, ?DEFAULT_TTL).

checkout(Name, Timeout) ->
  case sherlock_pool:push_job_to_queue(Name, Timeout) of
    {ok, WorkerPid} ->
      Ref = sherlock_mon_wrkr:monitor_me(Name, WorkerPid),
      {ok, WorkerPid, Ref};
    Reason ->
      {error, {Name, Reason}}
  end.



checkin(Name, {WorkerPid, Ref}) when is_pid(WorkerPid) ->
  sherlock_mon_wrkr:demonitor_me(Name, WorkerPid, Ref).



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
  erlang:error(not_implemented).