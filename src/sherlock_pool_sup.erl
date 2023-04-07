-module(sherlock_pool_sup).

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
-spec(start_link(Name :: any(), Args :: map()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Args) ->
  watson:create_namespace(Name, #{}),
  supervisor:start_link(watson:via(Name, {?MODULE, Name}), ?MODULE, {Name, Args}).

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
  io:format("~p - ~p | ~p ~n", [?MODULE, Name, Args]),
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{strategy => one_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},

  PoolSize = maps:get(size, Args, 1),
  Module   = maps:get(mod, Args, undefined_module),
  PoolArgs = maps:get(args, Args, undefined_arguments),

  sherlock_pool:new(Name, Args),

  Seq = lists:seq(0, PoolSize-1),

  ChildSpec = [spec_permanent(Name, Id, Module, PoolArgs) || Id <- Seq],

  {ok, {SupFlags, ChildSpec}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

spec_permanent(Name, Id, Module, Args) ->
  #{id => {Name, Id},
    start => {sherlock_worker, start_worker, [Name, Id, Module, Args]},
    restart => permanent,
    shutdown => 2000,
    type => worker,
    modules => dynamic}.