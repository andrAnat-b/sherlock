-module(sherlock_worker).

-callback start_worker(Args :: term()) -> Pid :: pid().

%% API
-export([start_worker/4]).


start_worker(Name, Id, Module, Args) ->
  Response = Module:start_worker(Args),
  case Response of
    {ok, Pid} ->
      {W, BindID}  = watch_fun(Name, Id),
      UW = unwatch_fun(Name, Id, BindID),
      watson:watch_random(Name, {W, UW}, Pid),
      Response;
    Other -> Other
  end.

watch_fun(Name, _Id) ->
  BindID = sherlock_pool:get_free_bind_id_idx(Name),
  Fun = fun(Pid) ->
    io:format("===========================================~n"),
    io:format("Name ~p Pid ~p BindId ~p~n", [Name, Pid, BindID]),
    io:format("===========================================~n"),
    sherlock_pool:add_worker(Name, Pid, BindID)
  end,
  {Fun, BindID}.

unwatch_fun(Name, _Id, BindID) ->
  fun(Pid) ->
    sherlock_pool:free_bind_id_idx(Name, BindID),
    sherlock_pool:sub_worker(Name, Pid, BindID)
  end.