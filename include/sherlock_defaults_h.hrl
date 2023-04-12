-ifndef(SHERLOCK_DEFAULT).
  -define(SHERLOCK_DEFAULT, true).

  -record('DOWN',{ref, type, id, reason}).

-else.
-endif.
