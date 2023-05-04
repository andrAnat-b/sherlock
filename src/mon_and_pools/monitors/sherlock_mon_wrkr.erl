-module(sherlock_mon_wrkr).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([start_link/1]).
-export([monitor_me/2]).
-export([demonitor_me/2]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_mon_wrkr_state, {name, monitors = #{}, objects = #{}}).
-record(monitor, {caller, object}).
-record(demonitor, {caller, object}).

%%%===================================================================
%%% API
%%%===================================================================

monitor_me(Name, WorkerPid) ->
  Me = self(),
  Spread = sherlock_pool:mx_size(Name),
  Id = erlang:phash([Me, WorkerPid], Spread),
  MonitPid = sherlock_registry:whereis_name({?MODULE, Name, Id}),
  gen_server:call(MonitPid, #monitor{caller = Me, object = WorkerPid}).

demonitor_me(Name, WorkerPid) ->
  Me = self(),
  Spread = sherlock_pool:mx_size(Name),
  Id = erlang:phash([Me, WorkerPid], Spread),
  MonitPid = sherlock_registry:whereis_name({?MODULE, Name, Id}),
  gen_server:cast(MonitPid, #monitor{caller = Me, object = WorkerPid}).

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link({any(), any()}) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link({Name, Id}) ->
  gen_server:start_link(sherlock_registry:via({?MODULE, Name, Id}), ?MODULE, {Name, Id}, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_mon_wrkr_state{}} | {ok, State :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init({Name, _Id}) ->
  {ok, #sherlock_mon_wrkr_state{name = Name}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_mon_wrkr_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_mon_wrkr_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_mon_wrkr_state{}} |
                   {noreply, NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_mon_wrkr_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_mon_wrkr_state{}}).
handle_call(#monitor{caller = Caller, object = Object}, _From, State = #sherlock_mon_wrkr_state{objects = O, monitors = M}) ->
  MRef = erlang:monitor(Caller, Object),
  {reply, MRef, State#sherlock_mon_wrkr_state{monitors = M#{Caller => MRef}, objects = O#{MRef => Object}}};
handle_call(_Request, _From, State = #sherlock_mon_wrkr_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_mon_wrkr_state{}) ->
  {noreply, NewState :: #sherlock_mon_wrkr_state{}} |
  {noreply, NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mon_wrkr_state{}}).
handle_cast(#demonitor{caller = Caller, object = WorkerPid}, State = #sherlock_mon_wrkr_state{monitors = M, objects = O}) ->
  {MRef, NewM} = maps:take(Caller, M),
  erlang:demonitor(MRef, [flash]),
  {WorkerPid, NewO} = maps:take({MRef, Caller}, O),
  sherlock_pool:push_worker(State#sherlock_mon_wrkr_state.name, WorkerPid),
  {noreply, State#sherlock_mon_wrkr_state{monitors = NewM, objects = NewO}};
handle_cast(_Request, State = #sherlock_mon_wrkr_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_mon_wrkr_state{}) ->
  {noreply, NewState :: #sherlock_mon_wrkr_state{}} |
  {noreply, NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mon_wrkr_state{}}).
handle_info(#'DOWN'{ref = MonitorRef, type = process, id = Caller, reason = _}, State = #sherlock_mon_wrkr_state{monitors = M, objects = O}) ->
  {MonitorRef, NewM} = maps:take(Caller, M),
  {WorkerPid,  NewO} = maps:take({MonitorRef, Caller}, O),
  sherlock_pool:push_worker(State#sherlock_mon_wrkr_state.name, WorkerPid),
  {noreply, State#sherlock_mon_wrkr_state{monitors = NewM, objects = NewO}};
handle_info(_Info, State = #sherlock_mon_wrkr_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_mon_wrkr_state{}) -> term()).
terminate(_Reason, _State = #sherlock_mon_wrkr_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_mon_wrkr_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_mon_wrkr_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_mon_wrkr_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
