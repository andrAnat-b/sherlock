-module(sherlock_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/2, add_child/2, rem_child/2]).

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

add_child(Name, Args) ->
  supervisor:start_child(watson:whereis_name(watson:via(Name, {?MODULE, Name})), Args).

rem_child(Name, ChildPid) ->
  supervisor:terminate_child(watson:whereis_name(watson:via(Name, {?MODULE, Name})), watson:whereis_name(watson:via(Name, ChildPid))).


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
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{strategy => one_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},

  PoolSize   = maps:get(min_size,    Args, 1),
  WorkerArgs = maps:get(worker_args, Args, #{state => 0}),
  Module     = maps:get(mod,         Args, sherlock_uniworker),
  Function   = maps:get(fn,          Args, start_worker),
  PoolArgs   = maps:get(args,        Args, [Name, Module, WorkerArgs]),

  sherlock_pool:new(Name, Args),

  Seq = lists:seq(0, PoolSize-1),

  ChildSpec = [spec_permanent(Name, Id, Module, Function, PoolArgs) || Id <- Seq],

  {ok, {SupFlags, ChildSpec}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

spec_permanent(Name, Id, Module, Function, Args) ->
  #{id => watson:via(Name, {Name, Id}),
    start => {Module, Function, Args},
    restart => transient,
    shutdown => 2000,
    type => worker,
    modules => dynamic}.