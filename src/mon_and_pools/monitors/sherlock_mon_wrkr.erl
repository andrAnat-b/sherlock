-module(sherlock_mon_wrkr).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([start_link/1]).
-export([monitor_me/2]).
-export([monitor_it/3]).
-export([demonitor_me/3]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_mon_wrkr_state, {name, monitors = #{}}).
-record(monitor, {caller, object}).
-record(demonitor, {caller, object, ref}).

%%%===================================================================
%%% API
%%%===================================================================

monitor_me(Name, WorkerPid) ->
  monitor_it(Name, self(), WorkerPid).
monitor_it(Name, Me, WorkerPid) ->
  Spread = sherlock_config:mx_size(Name),
  Id = os:perf_counter() rem Spread,
  MonitPid = sherlock_registry:whereis_name({?MODULE, Name, Id}),
  gen_server:call(MonitPid, #monitor{caller = Me, object = WorkerPid}).

demonitor_me(Name, WorkerPid, Ref) ->
  Caller = self(),
  MTab = sherlock_config:m_tab(Name),
  [{{Caller, Ref}, WorkerPid, MonitPid}] = ets:lookup(MTab, {Caller, Ref}),  %% @todo rewrite to lookup element
  gen_server:cast(MonitPid, #demonitor{caller = Caller, object = WorkerPid, ref = Ref}).

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link({any(), any()}) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link({Name, Id, TabRef}) ->
  gen_server:start_link(sherlock_registry:via({?MODULE, Name, Id}), ?MODULE, {Name, Id, TabRef}, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_mon_wrkr_state{}} | {ok, State :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init({Name, _Id, TabRef}) ->
  {ok, #sherlock_mon_wrkr_state{name = Name, monitors = TabRef}}.

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
handle_call(#monitor{caller = Caller, object = WorkerPid}, From, State = #sherlock_mon_wrkr_state{monitors = M}) ->
  MRef = erlang:monitor(process, Caller),
  ets:insert(M, {{Caller, MRef}, WorkerPid, self()}),
  gen_server:reply(From , MRef),
  {noreply, State};
handle_call(_Request, _From, State = #sherlock_mon_wrkr_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_mon_wrkr_state{}) ->
  {noreply, NewState :: #sherlock_mon_wrkr_state{}} |
  {noreply, NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mon_wrkr_state{}}).
handle_cast(#demonitor{caller = Caller, object = WorkerPid, ref = Ref}, State = #sherlock_mon_wrkr_state{monitors = M}) ->
  MonitorProc = self(),
  [{{Caller, MRef}, WorkerPid, MonitorProc}] = ets:take(M, {Caller, Ref}),
  erlang:demonitor(MRef, [flush]),
  case sherlock_pool:push_worker(State#sherlock_mon_wrkr_state.name, WorkerPid, nocall) of
    ok -> ok;
    {NewCaller, NewMref, NewMessage, Main, Id} ->
      ets:insert(M, {{NewCaller, NewMref}, WorkerPid, MonitorProc}),
      NewCaller ! NewMessage,
      ets:delete(Main, Id)
  end,
  {noreply, State};
handle_cast(_Request, State = #sherlock_mon_wrkr_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_mon_wrkr_state{}) ->
  {noreply, NewState :: #sherlock_mon_wrkr_state{}} |
  {noreply, NewState :: #sherlock_mon_wrkr_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mon_wrkr_state{}}).
handle_info(#'DOWN'{ref = MRef, type = process, id = Caller, reason = _}, State = #sherlock_mon_wrkr_state{monitors = M}) ->
  MonitorProc = self(),
  [{{Caller, MRef}, WorkerPid, MonitorProc}] = ets:take(M, {Caller, MRef}),
  case sherlock_pool:push_worker(State#sherlock_mon_wrkr_state.name, WorkerPid, nocall) of
    ok -> ok;
    {NewCaller, NewMref, NewMessage, Main, Id} ->
      ets:insert(M, {{NewCaller, NewMref}, WorkerPid, MonitorProc}),
      NewCaller ! NewMessage,
      ets:delete(Main, Id)
  end,
  {noreply, State};
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
