-module(sherlock_pool_holder).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_pool_holder_state, {monitors = #{}, workers = [], secret, name, args}).

-record(resize, {secret}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link({any(), any()}) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link({Name, Args}) ->
  gen_server:start_link(sherlock_registry:via({?SERVER, Name}), ?MODULE, {Name, Args}, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_pool_holder_state{}} | {ok, State :: #sherlock_pool_holder_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init({Name, Args}) ->
  sherlock_pool:create(Name, Args),
  WorkersWithRefs = do_start_childs(Args),
  [sherlock_pool:push_worker(Name, WorkerPid) || {_ , WorkerPid} <- WorkersWithRefs],
  Monitors = #{ MRef => WorkerPid || {MRef, WorkerPid} <- WorkersWithRefs},
  Workers = [WorkerPid || {_ , WorkerPid} <- WorkersWithRefs],
  Secret = erlang:make_ref(),
  resize(Secret),
  {ok, #sherlock_pool_holder_state{secret = Secret, monitors = Monitors, workers = Workers, name = Name, args = Args}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_pool_holder_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_pool_holder_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_pool_holder_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_pool_holder_state{}} |
                   {noreply, NewState :: #sherlock_pool_holder_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_pool_holder_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_pool_holder_state{}}).
handle_call(_Request, _From, State = #sherlock_pool_holder_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_pool_holder_state{}) ->
  {noreply, NewState :: #sherlock_pool_holder_state{}} |
  {noreply, NewState :: #sherlock_pool_holder_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_pool_holder_state{}}).
handle_cast(_Request, State = #sherlock_pool_holder_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_pool_holder_state{}) ->
  {noreply, NewState :: #sherlock_pool_holder_state{}} |
  {noreply, NewState :: #sherlock_pool_holder_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_pool_holder_state{}}).
handle_info(#resize{secret = S}, State = #sherlock_pool_holder_state{secret = S, workers = W, name = Name, args = Args}) ->
  do_resize_pool(Name, W, Args),
  resize(S),
  {noreply, State};
handle_info(_Info, State = #sherlock_pool_holder_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_pool_holder_state{}) -> term()).
terminate(_Reason, _State = #sherlock_pool_holder_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_pool_holder_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_pool_holder_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_pool_holder_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


do_start_childs(Args) ->
  {M, F, A} = maps:get(mfa, Args),
  MinSize = maps:get(min_size, Args),
  [do_init_start(M, F, A) || lists:seq(1, MinSize)].

do_init_start(M, F, A) ->
  case erlang:apply(M, F, A) of
    {ok, Pid} -> {erlang:monitor(process, Pid), Pid};
    {ok, Pid, _Extra} -> {erlang:monitor(process, Pid), Pid};
    _Reason ->
      throw({?MODULE, {?FUNCTION_NAME, _Reason}, {M, F, A}})
  end.

resize(Secret) ->
  erlang:send_after(1000, self(), #resize{secret = Secret}).

do_resize_pool(Name, W, Args) ->
  ActualSize = erlang:length(W),
  sherlock_pool:update_csize(Name, ActualSize),
  QID = sherlock_pool:get_qid(Name),
  WID = sherlock_pool:get_wid(Name),
  {QID, WID, Args}.