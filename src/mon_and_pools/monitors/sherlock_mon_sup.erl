-module(sherlock_mon_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%% @doc Starts the supervisor
-spec(start_link(any()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link({Name, Args}) ->
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
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,
  SupFlags = #{strategy => one_for_one,
               intensity => MaxRestarts,
               period => MaxSecondsBetweenRestarts},

  MaxSize = maps:get(max_size, Args),

  IDList = lists:seq(0, MaxSize -1),

  Children = [child_spec(Name, Id) || Id <- IDList],

  {ok, {SupFlags, Children}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

child_spec(Name, Id) ->
  #{id => {sherlock_mon_wrkr, Id},
    start => {sherlock_mon_wrkr, start_link, [{Name, Id}]},
    restart => permanent,
    shutdown => 2000,
    type => worker,
    modules => ['sherlock_mon_wrkr']}.