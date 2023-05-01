-module(sherlock_meta).

-include_lib("syntax_tools/include/merl.hrl").
%% API
-export([reconfig/0]).


reconfig() ->
  PoolNames = sherlock_pool:get_all_poolnames(),
  ConstHeader = [
    "-module(sherlock_config).",
    "-export([w_tab/1]).",
    "-export([q_tab/1]).",
    "-export([mx_size/1]).",
    "-export([m_tab/1])."] ++
    ["w_tab("++lists:flatten(io_lib:format("~w",[Poolname]))++") -> erlang:binary_to_term("++lists:flatten(io_lib:format("~w",[erlang:term_to_binary(sherlock_pool:w_tab(Poolname))]))++");"||Poolname<- PoolNames] ++
    ["w_tab(Poolname) -> sherlock_pool:w_tab(Poolname)."] ++
    ["q_tab("++lists:flatten(io_lib:format("~w",[Poolname]))++") -> erlang:binary_to_term("++lists:flatten(io_lib:format("~w",[erlang:term_to_binary(sherlock_pool:q_tab(Poolname))]))++");"||Poolname<- PoolNames] ++
    ["q_tab(Poolname) -> sherlock_pool:q_tab(Poolname)."] ++
    ["m_tab("++lists:flatten(io_lib:format("~w",[Poolname]))++") -> erlang:binary_to_term("++lists:flatten(io_lib:format("~w",[erlang:term_to_binary(sherlock_pool:m_tab(Poolname))]))++");"||Poolname<- PoolNames] ++
    ["m_tab(Poolname) -> sherlock_pool:m_tab(Poolname)."]++
    ["mx_size("++lists:flatten(io_lib:format("~w",[Poolname]))++") -> erlang:binary_to_term("++lists:flatten(io_lib:format("~w",[erlang:term_to_binary(sherlock_pool:mx_size(Poolname))]))++");"||Poolname<- PoolNames] ++
    ["m_tab(Poolname) -> sherlock_pool:m_tab(Poolname)."]
  ,
  AST = merl:qquote(1, ConstHeader, []),
  code:unstick_mod(sherlock_config),
  merl:compile_and_load(AST).