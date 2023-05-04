-module(sherlock_worker).

-callback start_worker(Args :: term()) -> Pid :: pid().

%% API
-export([start_worker/3]).


start_worker(Name, Module, Args) ->
  Response = Module:start_worker(Args),
  case Response of
    {ok, Pid} ->
      WatchFun  = watch_fun(Name),
      UWatchFun = unwatch_fun(Name),
      watson:watch_random(Name, {WatchFun, UWatchFun}, Pid),
      Response;
    Other -> Other
  end.

watch_fun(Name) ->
  Fun = fun(Pid) ->
    sherlock_pool:join_pool(Name, Pid)
  end,
  Fun.

unwatch_fun(Name) ->
  fun(Pid) ->
    sherlock_pool:leave_pool(Name, Pid)
  end.