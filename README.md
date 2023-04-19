# Sherlock
Sherlock is an Erlang library that provides a 
connection pooling mechanism for any purposes. 
It aims to simplify the management of database connections 
in a concurrent environment.

<br />
This 'pool manager' without singletone process called 'manager' and based on ETS and counters. 
Works fine with pool overloads.

## API

`start_pool/2`
```erlang
    sherlock:start_pool(PoolName::any(), Options::#{}) -> any().
```
 
<br />
 
`stop_pool/1`
```erlang
    sherlock:stop_pool(PoolName::any()) -> any().
``` 

<br />
 
`checkout/1`
```erlang
    sherlock:checkout(PoolName::any()) -> 
        {ok, WorkerPid::pid(), MRef::reference()} | {error, Reason::any()}.
```

<br />
 
`checkout/2`
```erlang
    sherlock:checkout(PoolName::any(), Timeout::nonnegint()) -> 
        {ok, WorkerPid::pid(), MRef::reference()} | {error, Reason::any()}.
```

<br />
 
`checkin/2`
```erlang
    sherlock:checkin(PoolName::any(), {WorkerPid::pid(), MRef::reference()}) -> 
        any().
```

<br />
 
`transaction/2`
```erlang
    sherlock:transaction(PoolName::any(), Fun::function()) when is_function(Fun, 1) -> 
        Result::any() | {error, any()}.
```

<br />
 
`transaction/3`
```erlang
    sherlock:transaction(PoolName::any(), Fun::function(), Timeout::nonnegint()) when is_function(Fun, 1) -> 
        Result::any() | {error, any()}.
```

<br />

Example of usage with postgres epgsql driver:

`sys.config`
```erlang
[
    {sherlock, [
    {pools, #{
      test_database =>
        #{
          min_size => 4,  %% minimal size of pool
          max_size => 16, %% maximum pool size
          refresh => 50,  %% time in millis for checks enlarge/shrink pool
          mfa => {
            epgsql,
            connect,
            [#{
               host => "localhost",
               username => "postgres",
               password => "postgres",
               database => "postgres",
               port => 5432,
               timeout => 300,
               application_name => "sherlock_test_app"
            }]
          }
        }
    }}
  ]}
].
```

`sherlock_test.erl`
```erlang
-module(sherlock_test).

-define(POOL, test_database).
%% API
-export([make_request/2]).


make_request(SQL, Args) ->
  Fun = fun(WorkerPid) -> epgsql:equery(WorkerPid, SQL, Args) end,
  case sherlock:transaction(?POOL, Fun) of
    {error, _} = Error ->
      Error;
    Result ->
      Result
  end.
```