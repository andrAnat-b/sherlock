-module(sherlock_test_UNIT).

%% API
-export([simple_test/0]).


simple_test() ->
  application:ensure_all_started(sherlock),
  sherlock:create_pool(a, #{min_size => 2, max_size => 4}),
  sherlock:create_pool(b, #{min_size => 4, max_size => 4}),
%%  [erlang:spawn(fun()-> W = sherlock:checkout(a), timer:sleep(15000), sherlock:checkin(a, W) end)||_<-lists:seq(1, 8)].
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