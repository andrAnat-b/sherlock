-module(sherlock_registry).

-behaviour(gen_server).

%% API
-export([start_link/0]).

-export([via/1]).

-export([whereis_name/1]).
-export([register_name/2]).
-export([register_name/3]).
-export([unregister_name/1]).

-export([unregister_default_fun/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-record(sherlock_registry_state, {}).

%%%===================================================================
%%% API
%%%===================================================================

via(Name) ->
  {?FUNCTION_NAME, ?MODULE, Name}.

register_name(Name, Pid) ->
    register_name(Name, Pid, unregister_default_fun()).

register_name(Name, Pid, ReRegFun) ->
    case whereis_name(Name) of
        undefined ->
            case ets:insert_new(?MODULE, [{Name, Pid}, {Pid, Name}]) of
                true -> yes;
                _ -> no
            end;
        AnotherPid ->
            case ReRegFun(Name, Pid, AnotherPid) of
                none -> no;
                NewPid when (NewPid == Pid) ->
                    [ets:delete_object(?MODULE, Tup) || Tup <- [{Name, AnotherPid},{AnotherPid, Name}]],
                    register_name(Name, NewPid, ReRegFun);
                _ ->
                    no
            end
    end.

unregister_name(Entity) ->
  case ets:take(?MODULE, Entity) of
    [] -> ok;
    [{_, Mirror}] ->
      ets:take(?MODULE, Mirror),
      ok
  end.

whereis_name(NameOrPid) ->
    case ets:lookup(?MODULE, NameOrPid) of
        [{_, Mirror}|_] -> Mirror;
        _ -> undefined
    end.

unregister_default_fun() ->
    fun(_Name, PidNew, PidOld) ->
        case is_process_alive(PidOld) of
            true -> PidOld;
            _ -> PidNew
        end
    end.
%% @doc Spawns the server and registers the local name (unique)
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
%% @doc Initializes the server
-spec(init(Args :: term()) ->
  {ok, State :: #sherlock_registry_state{}} | {ok, State :: #sherlock_registry_state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  ets:new(?MODULE, [named_table, public, set, {read_concurrency, true}]),
  {ok, #sherlock_registry_state{}}.

%% @private
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #sherlock_registry_state{}) ->
                   {reply, Reply :: term(), NewState :: #sherlock_registry_state{}} |
                   {reply, Reply :: term(), NewState :: #sherlock_registry_state{}, timeout() | hibernate} |
                   {noreply, NewState :: #sherlock_registry_state{}} |
                   {noreply, NewState :: #sherlock_registry_state{}, timeout() | hibernate} |
                   {stop, Reason :: term(), Reply :: term(), NewState :: #sherlock_registry_state{}} |
                   {stop, Reason :: term(), NewState :: #sherlock_registry_state{}}).
handle_call(_Request, _From, State = #sherlock_registry_state{}) ->
  {reply, ok, State}.

%% @private
%% @doc Handling cast messages
-spec(handle_cast(Request :: term(), State :: #sherlock_registry_state{}) ->
  {noreply, NewState :: #sherlock_registry_state{}} |
  {noreply, NewState :: #sherlock_registry_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_registry_state{}}).
handle_cast(_Request, State = #sherlock_registry_state{}) ->
  {noreply, State}.

%% @private
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #sherlock_registry_state{}) ->
  {noreply, NewState :: #sherlock_registry_state{}} |
  {noreply, NewState :: #sherlock_registry_state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #sherlock_registry_state{}}).
handle_info(_Info, State = #sherlock_registry_state{}) ->
  {noreply, State}.

%% @private
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #sherlock_registry_state{}) -> term()).
terminate(_Reason, _State = #sherlock_registry_state{}) ->
  ok.

%% @private
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #sherlock_registry_state{},
                  Extra :: term()) ->
                   {ok, NewState :: #sherlock_registry_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State = #sherlock_registry_state{}, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
