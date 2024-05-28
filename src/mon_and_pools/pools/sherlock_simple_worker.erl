-module(sherlock_simple_worker).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_simple_worker_state, {args}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(any()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_simple_worker_state{}} | {ok, State :: #sherlock_simple_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init(Args) ->
  {ok, #sherlock_simple_worker_state{args = Args}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_simple_worker_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_simple_worker_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_simple_worker_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_simple_worker_state{}} |
                   {noreply, NewState :: #sherlock_simple_worker_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_simple_worker_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_simple_worker_state{}}).
handle_call(Request, _From, State = #sherlock_simple_worker_state{args = OldArgs}) when is_function(Request, 1) ->
  {Response, NewArgs} = Request(OldArgs),
  {reply, Response, State#sherlock_simple_worker_state{args = NewArgs}};
handle_call(_Request, _From, State = #sherlock_simple_worker_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_simple_worker_state{}) ->
  {noreply, NewState :: #sherlock_simple_worker_state{}} |
  {noreply, NewState :: #sherlock_simple_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_simple_worker_state{}}).
handle_cast(Request, State = #sherlock_simple_worker_state{args = OldArgs}) when is_function(Request, 1) ->
  {_Response, NewArgs} = Request(OldArgs),
  {noreply, State#sherlock_simple_worker_state{args = NewArgs}};
handle_cast(_Request, State = #sherlock_simple_worker_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_simple_worker_state{}) ->
  {noreply, NewState :: #sherlock_simple_worker_state{}} |
  {noreply, NewState :: #sherlock_simple_worker_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_simple_worker_state{}}).
handle_info(_Info, State = #sherlock_simple_worker_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_simple_worker_state{}) -> term()).
terminate(_Reason, _State = #sherlock_simple_worker_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_simple_worker_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_simple_worker_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_simple_worker_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
