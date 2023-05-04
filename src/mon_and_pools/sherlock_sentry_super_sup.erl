-module(sherlock_sentry_super_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_child/2]).
-export([stop_child/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).



%%%===================================================================
%%% API functions
%%%===================================================================
start_child(Name, Args) ->
  Spec = #{id => {sherlock_sentry_pool_sup, Name},
           start => {'sherlock_sentry_pool_sup', start_link, [Name, Args]},
           restart => transient,
           shutdown => 2000,
           type => supervisor,
           modules => ['sherlock_sentry_pool_sup']},
  supervisor:start_child(?MODULE, Spec).

stop_child(Name) ->
  supervisor:terminate_child(?SERVER, {sherlock_sentry_pool_sup, Name}),
  sherlock_pool:destroy(Name).

%% @doc Starts the supervisor
-spec(start_link() -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

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
init([]) ->
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{strategy => one_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},
  {ok, {SupFlags, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
