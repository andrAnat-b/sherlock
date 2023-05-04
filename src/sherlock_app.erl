-module(sherlock_app).

-behaviour(application).

%% Application callbacks
-export([start/2,
         stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
            StartArgs :: term()) ->
             {ok, pid()} |
             {ok, pid(), State :: term()} |
             {error, Reason :: term()}).
start(_StartType, _StartArgs) ->
  case sherlock_super_sup:start_link() of
    {ok, Pid} ->
      erlang:garbage_collect(Pid),
      do_start_preconfigured_pools(),
      erlang:garbage_collect(self()),
      {ok, Pid};
    Error ->
      Error
  end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_start_preconfigured_pools() ->
  Pools = application:get_env(sherlock:'_app_name_'(), pools, []),
  case is_list(Pools) of
    true ->
      [ sherlock:start_pool(Name, Args) || {Name, Args} <- Pools ];
    _ ->
      maps:foreach(fun(Name, Args) -> sherlock:start_pool(Name, Args) end, Pools)
  end.