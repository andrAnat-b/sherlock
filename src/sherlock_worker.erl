-module(sherlock_worker).

%% API
-export([start_link/4]).


start_link(PoolName, Mod, Fun, WorkerArglist) ->
  case erlang:apply(Mod, Fun, WorkerArglist) of
    {ok, Pid} ->
      case sherlock_pool:join_pool(PoolName, Pid) of
        {pool, oversize} ->
          proc_lib:spawn(fun() -> timer:sleep(50), sherlock_pool_sup:rem_child(PoolName, Pid) end),
          {ok, Pid};
        _Other ->
          {ok, Pid}
      end;
    Other ->
      Other
  end.