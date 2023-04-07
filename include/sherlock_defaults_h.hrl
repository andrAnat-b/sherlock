-ifndef(SHERLOCK_DEFAULT).
  -define(SHERLOCK_DEFAULT, true).

  -define(SHERLOCK_POOL_DEFAULT_TTL, 5000).
  -define(SHERLOCK_WAIT_UNTIL(TTL), erlang:system_time(millisecond) + TTL).

-else.
-endif.
