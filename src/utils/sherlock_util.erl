-module(sherlock_util).

%% API
-export([get_schedulers_online/0]).


get_schedulers_online() ->
  erlang:system_info(schedulers_online).