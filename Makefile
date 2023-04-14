PROJECT = sherlock
PROJECT_DESCRIPTION = 'Sherlock is a pool based on ets without centralized pool manager'
PROJECT_VERSION = $(GITDESCRIBE)

LOCAL_DEPS += syntax_tools
LOCAL_DEPS += compiler

DEPS += lager

dep_lager			= git https://github.com/erlang-lager/lager.git			3.9.2

ERLC_OPTS += '+inline'
ERLC_OPTS += '+{parse_transform, lager_transform}'
ERLC_OPTS += '+{lager_truncation_size, 65535}'
ERLC_OPTS += '+{parse_transform, ct_expand}'
ERLC_OPTS += '+debug'

include erlang.mk
