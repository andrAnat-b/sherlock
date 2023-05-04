-module(sherlock_config).

%% API
-export([q_tab/1]).
-export([w_tab/1]).
-export([m_tab/1]).
-export([mx_size/1]).



q_tab(PoolName) ->
  TabRef = sherlock_pool:q_tab(PoolName),
  TabRef.

w_tab(PoolName) ->
  TabRef = sherlock_pool:w_tab(PoolName),
  TabRef.

m_tab(PoolName) ->
  TabRef = sherlock_pool:m_tab(PoolName),
  TabRef.

mx_size(PoolName) ->
  sherlock_pool:mx_size(PoolName).