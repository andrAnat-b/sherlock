-module(sherlock_super_sup).

-behaviour(supervisor).

start_pool()

-export([start_link/0, init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  sherlock_pool:init(),

  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{
    strategy => rest_for_one,
    intensity => MaxRestarts,
    period => MaxSecondsBetweenRestarts
  },

  Sentry = #{
    id       => sherlock_sentry_super_sup,
    restart  => permanent,
    shutdown => 2000,
    start    => {sherlock_sentry_super_sup, start_link, []},
    type     => supervisor,
    modules  => dynamic
  },

  Registry = #{
             id       => sherlock_registry,
             restart  => permanent,
             shutdown => 2000,
             start    => {sherlock_registry, start_link, []},
             type     => worker,
             modules  => dynamic
           },


  {ok, {SupFlags, [Sentry, Registry]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================