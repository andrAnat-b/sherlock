-module(sherlock_sentry_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%% @doc Starts the supervisor
-spec(start_link(any(), any()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Args) ->
  supervisor:start_link(sherlock_registry:via({?MODULE, Name}), ?MODULE, {Name, Args}).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% @private
%% @doc Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
-spec(init(Args :: term()) ->
  {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
                     MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
        [ChildSpec :: supervisor:child_spec()]}}
  | ignore | {error, Reason :: term()}).
init({Name, Args}) ->
  MaxRestarts = 1,
  MaxSecondsBetweenRestarts = 1,
  SupFlags = #{strategy => rest_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},

  Monitors = #{id => {sherlock_mon_sup, Name},
             start => {sherlock_mon_sup, start_link, [{Name, Args}]},
             restart => permanent,
             shutdown => 2000,
             type => supervisor,
             modules => [sherlock_mon_sup]},

  Workers = #{id => {sherlock_pool_holder, Name},
             start => {sherlock_pool_holder, start_link, [{Name, Args}]},
             restart => permanent,
             shutdown => 2000,
             type => worker,
             modules => [sherlock_pool_holder]},

  {ok, {SupFlags, [Monitors, Workers]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
