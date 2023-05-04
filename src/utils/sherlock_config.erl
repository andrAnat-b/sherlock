-module(sherlock_config).

%% API
-export([main_tab/1]).
-export([m_tab/1]).
-export([mx_size/1]).



main_tab(PoolName) ->
  TabRef = sherlock_pool:main_tab(PoolName),
  TabRef.

m_tab(PoolName) ->
  TabRef = sherlock_pool:m_tab(PoolName),
  TabRef.

mx_size(PoolName) ->
  sherlock_pool:mx_size(PoolName).