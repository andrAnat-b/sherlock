-module(sherlock_super_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_pool_workers/2]).
-export([stop_pool_workers/1]).


%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%% @doc Starts the supervisor
-spec(start_link() -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_pool_workers(Name, Args) ->
  Spec = #{id => Name,
    start => {sherlock_pool_sup, start_link, [Name, Args]},
    restart => transient,
    shutdown => 2000,
    type => supervisor,
    modules => [sherlock_pool_sup]},
  supervisor:start_child(?SERVER, Spec).

stop_pool_workers(Name) ->
  supervisor:terminate_child(?SERVER, Name).

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
  sherlock_pool:'_new_main_'(),
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{strategy => one_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},


  {ok, {SupFlags, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================