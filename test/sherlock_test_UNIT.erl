-module(sherlock_test_UNIT).

%% API
-export([simple_test/0]).


simple_test() ->
%%  [erlang:spawn(fun()-> {ok, W, Ref} = sherlock:checkout(a, 10000), timer:sleep(1000), sherlock:checkin(a, {W, Ref}) end)||_<-lists:seq(1, 8000)].
  Seq = lists:seq(0, 1024),
  [erlang:spawn(fun() ->
    sherlock:transaction(test, fun(WorkerPid) ->
      is_pid(WorkerPid),
      pong = gen_server:call(WorkerPid, ping)
                               end)
     end)
    ||
    _ <- Seq
  ].