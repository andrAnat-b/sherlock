-module(sherlock_test_UNIT).

%% API
-export([simple_test/0]).


simple_test() ->
  application:ensure_all_started(sherlock),
  sherlock:create_pool(test, #{size => 2, args => [], module => sherlock_test_worker}),
  Seq = lists:seq(0, 1024),
  [ erlang:spawn(fun() ->
    sherlock:transaction(test, fun(WorkerPid) ->
      is_pid(WorkerPid),
      pong = gen_server:call(WorkerPid, ping)
                               end)
     end)
    ||
    _ <- Seq
  ].