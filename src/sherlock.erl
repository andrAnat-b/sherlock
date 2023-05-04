-module(sherlock).

-export([start_pool/2]).
-export([stop_pool/1]).

-export([checkout/1]).
-export([checkout/2]).
-export([checkin/2]).

-export([transaction/2]).
-export([transaction/3]).

-export([get_pool_metrics/0]).

-export(['_app_name_'/0]).


%% API
start_pool(Name, Opts) ->
  sherlock_pool:create(Name, Opts).

stop_pool(Name) ->
  sherlock_pool:destroy(Name).



checkout(Name) ->
  sherlock_pool:push_job_to_queue(Name).

checkout(Name, Timeout) ->
  case sherlock_pool:push_job_to_queue(Name, Timeout) of
    {ok, WorkerPid} ->
      watch_me,
      WorkerPid;
    Reason ->
      {error, {Name, Reason}}
  end.



checkin(Name, Pid) when is_pid(Pid) ->
  unwatch_me,
  sherlock_pool:push_worker(Name, Pid).



transaction(Name, Fun) when is_function(Fun, 1) ->
  case checkout(Name) of
    {error, _} = Error ->
      Error;
    Pid ->
      Result = Fun(Pid),
      checkin(Name, Pid),
      Result
  end.

transaction(Name, Fun, Timeout) when is_function(Fun, 1) ->
  case checkout(Name, Timeout) of
    {error, {timeout, TimedOut}} ->
      {timeout, {Name, TimedOut}};
    Pid ->
      Result = Fun(Pid),
      checkin(Name, Pid),
      Result
  end.



'_app_name_'() ->
  ?MODULE.

get_pool_metrics() ->
  erlang:error(not_implemented).