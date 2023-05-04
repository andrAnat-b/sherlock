-module(sherlock_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/2, add_child/2, rem_child/2, get_child_pids/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%% @doc Starts the supervisor
-spec(start_link(Name :: any(), Args :: map()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Args) ->
  _ = watson:create_namespace(Name, #{}),
  supervisor:start_link(watson:via(Name, {?MODULE, Name}), ?MODULE, {Name, Args}).

add_child(Name, Args) ->
  WArgs = maps:get(worker_args, Args),
  Module = maps:get(mod, Args),
  Function = maps:get(fn, Args),
  Spec = #{id => {Name, os:perf_counter()},
           start => {sherlock_worker, start_link, [Name, Module, Function, WArgs]},
           restart => transient,
           shutdown => 2000,
           type => worker,
           modules => dynamic},
  supervisor:start_child(watson:whereis_name(watson:via(Name, {?MODULE, Name})), Spec).

rem_child(Name, ChildPid) ->
  supervisor:terminate_child(watson:whereis_name(watson:via(Name, {?MODULE, Name})), watson:whereis_name(watson:via(Name, ChildPid))).

get_child_pids(Name) ->
  Ret = supervisor:which_children(watson:whereis_name(watson:via(Name, {?MODULE, Name}))),
  [ Child || {_Id, Child, _Type, _Modules} <- Ret].


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
  Module     = maps:get(mod,         Args, sherlock_uniworker),
  Function   = maps:get(fn,          Args, start_link),
  PoolArgs   = maps:get(args,        Args, [#{state => 0}]),

  sherlock_pool:new(Name, Args),

  Seq = lists:seq(0, PoolSize-1),

  ChildSpec = [spec_permanent(Name, os:perf_counter(), Module, Function, PoolArgs) || _ <- Seq],

  Overseer =  #{
    id => {Name, sherlock_pool_sentry},
    start => {sherlock_pool_sentry, start_link, [Name]},
    restart => transient,
    shutdown => 2000,
    type => worker,
    modules => dynamic
  },

  {ok, {SupFlags, ChildSpec ++ [Overseer]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

spec_permanent(Name, Id, Module, Function, Args) ->
  #{id => {Name, Id},
%%    start => {sherlock_uniworker, start_link, Args},
    start => {sherlock_worker, start_link, [Name, Module, Function, Args]},
    restart => transient,
    shutdown => 2000,
    type => worker,
    modules => dynamic}.