-module(sherlock_mokup_worker).

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_mokup_worker_state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(Name::any(), Args::any()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(_Name, Args) ->
    gen_server:start_link(?MODULE, Args, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_mokup_worker_state{}} | {ok, State :: #sherlock_mokup_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  {ok, #sherlock_mokup_worker_state{}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_mokup_worker_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_mokup_worker_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_mokup_worker_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_mokup_worker_state{}} |
                   {noreply, NewState :: #sherlock_mokup_worker_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_mokup_worker_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_mokup_worker_state{}}).
handle_call(ping, _From, State = #sherlock_mokup_worker_state{}) ->
  {reply, pong, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_mokup_worker_state{}) ->
  {noreply, NewState :: #sherlock_mokup_worker_state{}} |
  {noreply, NewState :: #sherlock_mokup_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mokup_worker_state{}}).
handle_cast(_Request, State = #sherlock_mokup_worker_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_mokup_worker_state{}) ->
  {noreply, NewState :: #sherlock_mokup_worker_state{}} |
  {noreply, NewState :: #sherlock_mokup_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_mokup_worker_state{}}).
handle_info(_Info, State = #sherlock_mokup_worker_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_mokup_worker_state{}) -> term()).
terminate(_Reason, _State = #sherlock_mokup_worker_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_mokup_worker_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_mokup_worker_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_mokup_worker_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
