-module(sherlock_pool_holder).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_pool_holder_state, {monitors = #{}, workers = [], mirror = #{}, secret, name, args}).

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
%%  resize(Secret),
  {ok, #sherlock_pool_holder_state{secret = Secret, monitors = Monitors, mirror = Mirrors, workers = Workers, name = Name, args = Args}}.

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
handle_info(#resize{secret = S}, State = #sherlock_pool_holder_state{secret = S, workers = W, name = Name, monitors = Mon, mirror = Mir, args = Args}) ->
  {NewMon, NewMir, NewW} = case do_resize_pool(Name, W, Args) of
    {monitor, NewWorkers} ->
      [sherlock_pool:push_worker(Name, WorkerPid) || {_ , WorkerPid} <- NewWorkers],
      Monitors = maps:from_list(NewWorkers),
      Mirrors = maps:from_list([{WorkerPid, MRef} || {MRef, WorkerPid} <- NewWorkers]),
      Workers = [WorkerPid || {_ , WorkerPid} <- NewWorkers],
      {maps:merge(Mon, Monitors), maps:merge(Mir, Mirrors), W ++ Workers};
    {demonitor, [StopMe]} ->
      ProcRef = maps:get(StopMe, Mir),
      erlang:demonitor(ProcRef, [flush]),
      erlang:exit(StopMe, normal),
      {maps:without([ProcRef], Mon), maps:without([StopMe], Mon), W -- [StopMe]}
  end,
  resize(S),
  {noreply, State#sherlock_pool_holder_state{monitors = NewMon, mirror = NewMir, workers = NewW}};
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
  erlang:send_after(10000, self(), #resize{secret = Secret}).

do_resize_pool(Name, W, Args) ->
  ActualSize = erlang:length(W),
  sherlock_pool:update_csize(Name, ActualSize),
  QID = sherlock_pool:get_qid(Name),
  WID = sherlock_pool:get_wid(Name),
  case QID > WID of
    true ->
      MaxSize = sherlock_pool:mx_size(Name),
      NewWorkers = do_enlarge_pool(Name, min(MaxSize - ActualSize, QID - WID), Args),
      {monitor, NewWorkers};
    _ ->
      {monitor, []}
%%      case detail_check(QID, WID, ActualSize, Args) of
%%        stable -> {monitor, []};
%%        reduce ->
%%          {ok, WorkerToStop} = sherlock_pool:push_job_to_queue(Name, infinity),
%%          {demonitor, [WorkerToStop]}
%%      end
  end.

do_enlarge_pool(_Name, 0, _Args) ->
  [];
do_enlarge_pool(Name, AdditionalSize, Args) ->
  do_enlarge_pool(Name, AdditionalSize, Args ,[]).

do_enlarge_pool(_Name, AdditionalSize, _Args, Acc) when AdditionalSize =< 0 -> Acc;
do_enlarge_pool(Name, AdditionalSize, Args, Acc) ->
  try
    {M, F, A} = maps:get(mfa, Args),
    Res = do_init_start(M, F, A),
    do_enlarge_pool(Name, AdditionalSize -1, Args, [Res|Acc])
  catch
      _  ->
        do_enlarge_pool(Name, AdditionalSize - 1, Args, Acc)
  end .
%%
%%detail_check(SameSize, SameSize, _ActualSize, _Args) ->
%%  stable;
%%detail_check(_QID, _WID, _ActualSize, _Args) ->
%%  reduce.