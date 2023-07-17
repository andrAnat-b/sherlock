-module(sherlock_pool_holder).

-behaviour(gen_server).
-include("sherlock_defaults_h.hrl").
%% API
-export([get_all_workers/1]).
-export([call/2]).
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(REFRESH, 5000).

-record(sherlock_pool_holder_state, {
  monitors = #{},
  workers = [],
  mirror = #{},
  secret,
  name,
  args,
  last_wid = 1,
  last_qid = 1,
  mstime = ?REFRESH
}).

-record(resize, {secret}).

%%%===================================================================
%%% API
%%%===================================================================
get_all_workers(Name) ->
  call(Name, ?FUNCTION_NAME).

call(Name, Comamnd) ->
  gen_server:call(sherlock_registry:via({?SERVER, Name}), Comamnd).


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
  process_flag(trap_exit, true),
  sherlock_pool:create(Name, Args),
  WorkersWithRefs = do_start_childs(Args),
  List = [sherlock_pool:push_worker(Name, WorkerPid, call) || {_ , WorkerPid} <- WorkersWithRefs],
  PoolSize = erlang:length(List),
  sherlock_pool:update_csize(Name, PoolSize),
  Monitors = maps:from_list(WorkersWithRefs),
  Mirrors = maps:from_list([{WorkerPid, MRef} || {MRef, WorkerPid} <- WorkersWithRefs]),
  Workers = [WorkerPid || {_ , WorkerPid} <- WorkersWithRefs],
  Secret = erlang:make_ref(),
  Refresh = maps:get(refresh, Args, ?REFRESH),
  State = #sherlock_pool_holder_state{
    secret = Secret,
    monitors = Monitors,
    mirror = Mirrors,
    workers = Workers,
    name = Name,
    args = Args,
    mstime = Refresh
  },
  resize(Secret, Refresh),
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
handle_call(get_all_workers, _From, State = #sherlock_pool_holder_state{}) ->
  {reply, State#sherlock_pool_holder_state.workers, State};
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
handle_info(#resize{secret = S}, State = #sherlock_pool_holder_state{secret = S, name = Name, mstime = MSTime}) ->
  #sherlock_pool_holder_state{workers = Workers} = State,
  ActualSizePrev = erlang:length(Workers),
  sherlock_pool:update_csize(Name, ActualSizePrev),
  Direction = pool_resize_direction(Name, ActualSizePrev),
%%  lager:log(debug, self(), "[V] RESIZE DIRECTION ~p", [Direction]),
  {AdditionalWorkersPid, NewState} = make_resize(Direction, State, []),
  [sherlock_pool:push_worker(Name, Pid, call) || Pid <- AdditionalWorkersPid],
  resize(S, MSTime),
  {noreply, NewState};
handle_info(#'DOWN'{ref = MonRef, id = OldWorker, reason = Reason}, State = #sherlock_pool_holder_state{name = Name, workers = Work}) ->
  logger:error("Worker from (~p) fails with reason ~p", [Name, Reason]),
  sherlock_pool:occup(Name),
  #sherlock_pool_holder_state{mirror = Mir, monitors = Mon} = State,
  {MonRef, NewMir} = maps:take(OldWorker, Mir),
  NewMon = maps:without([MonRef], Mon),
  NewWorkersList = [Pid ||Pid<-Work, Pid =/= OldWorker],
  State0 = State#sherlock_pool_holder_state{monitors = NewMon, mirror = NewMir, workers = NewWorkersList},
  {[NewWorker], NewState} = make_resize({enlarge, 1}, State0, []),
%%  lager:log(debug, self(),"[X] RESIZE DIRECTION ~p", [{enlarge, 1}]),
  sherlock_pool:replace_worker(Name, OldWorker, NewWorker),
  {noreply, NewState};
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
      logger:error("Initialization fails with reason ~p",[_Reason]),
      throw({?MODULE, {?FUNCTION_NAME, _Reason}, {M, F, A}})
  end.

resize(Secret, MSTime) ->
  erlang:send_after(MSTime, self(), #resize{secret = Secret}).

pool_resize_direction(Name, CurSize) ->
  Max = sherlock_pool:mx_size(Name), % 16
  Min = sherlock_pool:mn_size(Name), % 4
  Busy = sherlock_pool:get_occupied(Name), % -16
  Director = (Min + Busy),
  if
    Director > 0 ->
      {enlarge, min(Max - CurSize, Director)};
    Director == 0 ->
      {enlarge, 0};
    Director < 0 ->
      {shrink, 1}
  end.

make_resize({enlarge, 0}, State, Acc) ->
  {Acc, State};
make_resize({enlarge, N}, State, Acc) ->
  #sherlock_pool_holder_state{args = Args, workers = WrkL, monitors = Mon, mirror = Mir} = State,
  {M, F, A} = maps:get(mfa, Args),
  try
    {MRef, WorkerPid} = do_init_start(M, F, A),
    NewWrkL = [WorkerPid|WrkL],
    NewMon = maps:merge(Mon, #{MRef => WorkerPid}),
    NewMir = maps:merge(Mir, #{WorkerPid => MRef}),
    NewState = State#sherlock_pool_holder_state{workers = NewWrkL, monitors = NewMon, mirror = NewMir},
    make_resize({enlarge, N-1}, NewState, [WorkerPid|Acc])
  catch
    _ ->
      make_resize({enlarge, N-1}, State, Acc)
  end;
make_resize({shrink, 0}, State, Acc) ->
  {Acc, State};
make_resize({shrink, N}, State = #sherlock_pool_holder_state{name = Name}, Acc) ->
  case sherlock_pool:push_job_to_queue(Name, 5) of
    {ok, Worker, _Monref} ->
      #sherlock_pool_holder_state{name = Name, workers = WrkL, monitors = Mon, mirror = Mir} = State,
      NewWorkerL = [Pid || Pid <- WrkL, Pid /= Worker],
      {Ref, NewMir} = maps:take(Worker, Mir),
      NewMon = maps:without([Ref], Mon),
      catch erlang:unlink(Worker),
      erlang:demonitor(Ref, [flush]),
      erlang:exit(Worker, stop),
      NewState = State#sherlock_pool_holder_state{name = Name, monitors = NewMon, mirror = NewMir, workers = NewWorkerL},
      make_resize({shrink, N-1}, NewState, Acc);
    _ ->
      make_resize({shrink, N-1}, State, Acc)
  end.
