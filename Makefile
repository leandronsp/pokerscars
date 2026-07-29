SHELL = /bin/bash
.DEFAULT_GOAL := help

# ---- shared configuration (available to every included makefile) ----

DC  := docker compose
WEB := $(DC) exec web

# Host ports. Kept clear of the ranges the other local stacks claim
# (4000/4010/4200 web, 5432-5443 postgres). Export a different value to move them.
export WEB_PORT ?= 4300
export DB_PORT  ?= 5444

.PHONY: help

help: ## Show every target, grouped by context
	@printf "\n\033[1mpokerscars\033[0m — make targets\n"
	@awk 'BEGIN {FS = ":.*##"} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
		/^[a-zA-Z._-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\n"

# ---- bounded contexts (one makefile each) ----
include makefiles/dev.mk
include makefiles/test.mk
