-module(sherlock).

-export([create_pool/2]).
-export([stop_pool/1]).

-export([checkout/1]).
-export([checkout/2]).
-export([checkin/2]).

-export([transaction/2]).
-export([transaction/3]).

-export(['_app_name_'/0]).


%% API
create_pool(Name, Opts) ->
  sherlock_super_sup:start_pool_workers(Name, Opts).

stop_pool(Name) ->
  sherlock_pool:stop(Name),
  sherlock_super_sup:stop_pool_workers(Name),
  watson:destroy_namespace(Name).



checkout(Name) ->
  sherlock_pool:lease_worker(Name).

checkout(Name, Timeout) ->
  sherlock_pool:lease_worker(Name, Timeout).



checkin(_Name, {timeout, _}) -> ok;
checkin(Name, Pid) ->
  sherlock_pool:release_worker(Name, Pid).



transaction(Name, Fun) when is_function(Fun, 1) ->
  case checkout(Name) of
    {error, {timeout, Timeout}} ->
      {timeout, {Name, Timeout}};
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