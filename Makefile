PROJECT = sherlock
PROJECT_DESCRIPTION = 'Sherlock is a pool based on ets without centralized pool manager'
PROJECT_VERSION = $(GITDESCRIBE)

LOCAL_DEPS += syntax_tools
LOCAL_DEPS += compiler

include erlang.mk
