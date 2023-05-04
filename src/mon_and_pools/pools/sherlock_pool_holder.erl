-module(sherlock_pool_holder).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_pool_holder_state, {
  monitors = #{},
  workers = [],
  mirror = #{},
  secret,
  name,
  args,
  last_wid = 0,
  last_qid = 0
}).

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
  List = [sherlock_pool:push_worker(Name, WorkerPid) || {_ , WorkerPid} <- WorkersWithRefs],
  PoolSize = erlang:length(List),
  sherlock_pool:update_csize(Name, PoolSize),
  Monitors = maps:from_list(WorkersWithRefs),
  Mirrors = maps:from_list([{WorkerPid, MRef} || {MRef, WorkerPid} <- WorkersWithRefs]),
  Workers = [WorkerPid || {_ , WorkerPid} <- WorkersWithRefs],
  Secret = erlang:make_ref(),
  LastQid =  sherlock_pool:get_qid(Name),
  LastWid =  sherlock_pool:get_wid(Name),
  resize(Secret),
  State = #sherlock_pool_holder_state{
    secret = Secret,
    monitors = Monitors,
    mirror = Mirrors,
    workers = Workers,
    name = Name,
    args = Args,
    last_qid = LastQid,
    last_wid = LastWid
  },
  {ok, State}.

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
handle_info(#resize{secret = S}, State = #sherlock_pool_holder_state{secret = S, name = Name}) ->
  #sherlock_pool_holder_state{workers = Workers, last_qid = Q, last_wid = W} = State,
  ActualSizePrev = erlang:length(Workers),
  sherlock_pool:update_csize(Name, ActualSizePrev),
  Direction = pool_resize_direction(Name, ActualSizePrev, W, Q),
  NewState = make_resize(Direction, State),
  resize(S),
  {noreply, State#sherlock_pool_holder_state{}};
handle_info(#'DOWN'{}, State = #sherlock_pool_holder_state{}) ->
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
  [do_init_start(M, F, A) || _ <- lists:seq(1, MinSize)].

do_init_start(M, F, A) ->
  case erlang:apply(M, F, A) of
    {ok, Pid} when is_pid(Pid) -> {erlang:monitor(process, Pid), Pid};
    {ok, Pid, _Extra} when is_pid(Pid) -> {erlang:monitor(process, Pid), Pid};
    _Reason ->
      throw({?MODULE, {?FUNCTION_NAME, _Reason}, {M, F, A}})
  end.

resize(Secret) ->
  erlang:send_after(500, self(), #resize{secret = Secret}).

pool_resize_direction(Name, ActualSizePrev, LWid, LQid) ->
  QID = sherlock_pool:get_qid(Name),
  WID = sherlock_pool:get_wid(Name),
  RQid = get_real_val(QID, LQid),
  RWid = get_real_val(WID, LWid),
  case RQid - RWid of
    More when More > 0 ->
      Max = sherlock_pool:mx_size(Name),
      Enlarge = min(More, (Max - ActualSizePrev)),
      {enlarge, Enlarge};
    Less when Less < 0 ->
      {shrink, 1};
    _ ->
      {enlarge, 0}
  end.

get_real_val(Cur, Prev) ->
  if
    Cur > Prev -> Cur;
    true -> Cur +?CTH
  end.

make_resize({enlarge, 0}, State) ->
  State;
make_resize({enlarge, _N}, State) ->
  State;
make_resize({shrink, _N}, State) ->
  State.
