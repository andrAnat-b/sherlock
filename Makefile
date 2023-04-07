PROJECT = sherlock
PROJECT_DESCRIPTION = 'Sherlock is a pool based on ets without centralized pool manager'
PROJECT_VERSION = $(GITDESCRIBE)

DEPS += watson

dep_watson = git https://github.com/andranat-b/watson.git

include erlang.mk
