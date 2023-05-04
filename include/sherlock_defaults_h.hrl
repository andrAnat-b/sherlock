-ifndef(SHERLOCK_DEFAULT).
  -define(SHERLOCK_DEFAULT, true).

  -record('DOWN',{ref, type, id, reason}).
%%  -define(CTH, 1 bsl 64).
  -define(CTH, 18446744073709551616).
  -define(DEFAULT_TTL, 5000).

-else.
-endif.
