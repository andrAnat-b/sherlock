-module(sherlock_pool_sentry).

-behaviour(gen_server).

-define(MAX_COUNT, 10).
%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-record(resize, {ref = erlang:make_ref()}).
-record(sherlock_pool_sentry_state, {name, secret, counter = 0}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Spawns the server and registers the local name (unique)
-spec(start_link(any()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name) ->
  gen_server:start_link(watson:via(Name, {?MODULE, Name}), ?MODULE, Name, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_pool_sentry_state{}} | {ok, State :: #sherlock_pool_sentry_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init(Name) ->
  Message = #resize{},
  erlang:send(self(), Message#resize.ref),
  {ok, #sherlock_pool_sentry_state{secret = Message#resize.ref, name = Name}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_pool_sentry_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_pool_sentry_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_pool_sentry_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_pool_sentry_state{}} |
                   {noreply, NewState :: #sherlock_pool_sentry_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_pool_sentry_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_pool_sentry_state{}}).
handle_call(_Request, _From, State = #sherlock_pool_sentry_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_pool_sentry_state{}) ->
  {noreply, NewState :: #sherlock_pool_sentry_state{}} |
  {noreply, NewState :: #sherlock_pool_sentry_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_pool_sentry_state{}}).
handle_cast(_Request, State = #sherlock_pool_sentry_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_pool_sentry_state{}) ->
  {noreply, NewState :: #sherlock_pool_sentry_state{}} |
  {noreply, NewState :: #sherlock_pool_sentry_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_pool_sentry_state{}}).
handle_info(#resize{ref = Secret} = Msg, State = #sherlock_pool_sentry_state{secret = Secret, name = Name, counter = C}) ->
  case try_resize_pool(Name, C) of
    dynamic ->
      erlang:send_after(500, self(), Msg),
      NewC = case {C < ?MAX_COUNT, C} of
               {true, Counter} -> Counter + 1;
               _ -> 0
             end,
      {noreply, State#sherlock_pool_sentry_state{counter = NewC}};
    static ->
      {stop, normal, State}
  end;
handle_info(Secret, State = #sherlock_pool_sentry_state{secret = Secret}) ->
  erlang:send_after(1000, self(), #resize{ref = Secret}),
  {noreply, State};
handle_info(_Info, State = #sherlock_pool_sentry_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_pool_sentry_state{}) -> term()).
terminate(_Reason, _State = #sherlock_pool_sentry_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_pool_sentry_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_pool_sentry_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_pool_sentry_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


try_resize_pool(PoolName, Counter) ->
  Args    = sherlock_pool:get_pool_opts(PoolName),
  Max     = maps:get(max_size, Args),
  Min     = maps:get(min_size, Args),
  if
    Min == Max -> static;
    true ->
      resize_pool(PoolName, Args, Counter),
      dynamic
  end.


resize_pool(PoolName, Args, Counter) ->
  Size    = maps:get(size, Args),
  Max     = maps:get(max_size, Args),
  Min     = maps:get(min_size, Args),
  case ets:info(sherlock_pool:get_standby(PoolName), size) of
    StbCSize when (StbCSize < Size) and (Size < Max) ->
      MaxAllowedEnlarge = Max - Min,
      QueueSize = ets:info(sherlock_pool:get_queue(PoolName), size),
      io:format("ENLARGE ~p~n~n~n", [[{'PoolName', PoolName}, {'MaxAllowedEnlarge', MaxAllowedEnlarge}, {'QueueSize', QueueSize}]]),
      do_enlarge(PoolName, Args, min(MaxAllowedEnlarge, QueueSize));
    StbCSize when (Size > Min) and (Counter == ?MAX_COUNT) and (StbCSize > 1) ->
      shrink_pool(PoolName);
    _ ->
      nop
  end.


do_enlarge(PoolName, Args, EnlargeSize) when EnlargeSize > 0 ->
  io:format("ENLARGE ~p~n~n~n", [[PoolName, Args, EnlargeSize]]),
  [enlarge_pool(PoolName, Args) || _ <- lists:seq(1, EnlargeSize)];
do_enlarge(_PoolName, _Args, _EnlargeSize) ->
  nop.



enlarge_pool(PoolName, Args) ->
  sherlock_pool_sup:add_child(PoolName, Args).

shrink_pool(PoolName) ->
  case sherlock:checkout(PoolName, 10000) of
    {error, {timeout, _TimedOut}} ->
      ok;
    WorkerPid ->
      case sherlock_pool:leave_pool(PoolName, WorkerPid) of
        {pool, undersize} ->
          ok;
        Pid ->
          sherlock_pool:usage_decr(PoolName),
          sherlock_pool_sup:rem_child(PoolName, Pid)
      end
  end.
