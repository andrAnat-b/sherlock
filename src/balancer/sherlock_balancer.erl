-module(sherlock_balancer).
-include_lib("stdlib/include/ms_transform.hrl").

-define(ROUND_ROBIN,  0).
-define(RANDOM_ROBIN, 1).
-define(HASH_ROBIN,   2).
-define(LEAST_ROBIN,  3).

-define(N_ROUND_ROBIN,  round_robin).
-define(N_RANDOM_ROBIN, random_robin).
-define(N_HASH_ROBIN,   hash).
-define(N_LEAST_ROBIN,  least).

-define(K_ALG, 2).
-define(K_CUR, 2).
-define(K_MAX, 2).
%% API
-export([init/0]).
-export([new/2]).
-export([destroy/1]).

-export([add_to_balancer/2]).
-export([rem_from_balancer/1]).
-export([balance/1]).

-export([info/0]).
-export([info/1]).

init() ->
  ets:new(?MODULE, [named_table, public, set]).

new(Name, Opts) ->
  Algorythm  = algorytm_to_id(maps:get(alg, Opts, undefined)),
  ets:insert(?MODULE, {Name, Algorythm, 0, 0}).

add_to_balancer(Name, Entity) ->
  NewEnt = ets:update_counter(?MODULE, Name, {?K_MAX, 1}),
  ets:insert(?MODULE, {{Name, NewEnt}, Entity}).

rem_from_balancer(Name) ->
  NewEnt = ets:update_counter(?MODULE, Name, {?K_MAX, -1}),
  case ets:take(?MODULE, {Name, NewEnt+1}) of
    []            -> {error, {balancer, Name}};
    [{_, Entity}] -> {ok, Entity}
  end.

destroy(Name) ->
  do_destroy(Name),
  ets:delete(?MODULE, Name).

algorytm_to_id(?N_ROUND_ROBIN)  -> ?ROUND_ROBIN;
algorytm_to_id(?N_RANDOM_ROBIN) -> ?RANDOM_ROBIN;
algorytm_to_id(?N_HASH_ROBIN)   -> ?HASH_ROBIN;
algorytm_to_id(?N_LEAST_ROBIN)  -> ?LEAST_ROBIN;
algorytm_to_id(_)               -> ?ROUND_ROBIN.

id_to_alg_name(?ROUND_ROBIN)  -> ?N_ROUND_ROBIN;
id_to_alg_name(?RANDOM_ROBIN) -> ?N_RANDOM_ROBIN;
id_to_alg_name(?HASH_ROBIN)   -> ?N_HASH_ROBIN;
id_to_alg_name(?LEAST_ROBIN)  -> ?N_LEAST_ROBIN.

do_destroy(Name) ->
  do_destroy_2(Name, rem_from_balancer(Name)).

do_destroy_2(Name, {ok, _}) ->
  do_destroy_2(Name, rem_from_balancer(Name));
do_destroy_2(_, _) -> ok.

info() ->
  MS = ets:fun2ms(fun({Name, _, _, _}) -> Name end),
  [{Name, info(Name)} || Name <- ets:select(?MODULE, MS)].

info(Name) ->
  case ets:lookup(?MODULE, Name) of
    [] -> [{error, undefined}];
    [{_, Algorythm, Cur, Max}] ->
      [
        {alg, id_to_alg_name(Algorythm)},
        {cur, Cur},
        {max, Max}
      ]
  end.

balance(Name) ->
  Treshold = ets:update_counter(?MODULE, Name, {?K_MAX, 0}),
  [Next, ALG] = ets:update_counter(?MODULE, Name, [{?K_CUR, 1, Treshold, 0}, {?K_ALG, 0}]),
  AlgName = id_to_alg_name(ALG),
  BalancedID = do_calc_id(Name, AlgName, Treshold, Next),
  [{_, Entity}] = ets:lookup(?MODULE, {Name, BalancedID}),
  Entity.


do_calc_id(_Name, ?N_ROUND_ROBIN, _Treshold, Next)  ->  Next;
do_calc_id(_Name, ?N_RANDOM_ROBIN, Treshold, _Next) ->  erlang:round(rand:uniform(Treshold));
do_calc_id(_Name, ?N_HASH_ROBIN,   Treshold, Next)  ->  erlang:phash2({Treshold, Next}, Treshold);
do_calc_id(Name, ?N_LEAST_ROBIN,  Treshold, Next)  ->  erlang:error(not_implemented).