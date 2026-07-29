##@ Quality (the gate, in Docker)
.PHONY: check types lint test.run test.watch format

check: ## The gate: format, compile, credo, dialyzer, test
	@$(DC) exec -e MIX_ENV=test web mix check

types: ## Type checking only (compiler inference + dialyzer contracts)
	@$(DC) exec -e MIX_ENV=test web mix compile --warnings-as-errors
	@$(DC) exec -e MIX_ENV=test web mix dialyzer

lint: ## Credo only
	@$(DC) exec -e MIX_ENV=test web mix credo

test.run: ## Run the test suite
	@$(DC) exec -e MIX_ENV=test web mix test

test.watch: ## Run a single test file or line (make test.watch F=test/foo_test.exs:12)
	@$(DC) exec -e MIX_ENV=test web mix test $(F)

format: ## Rewrite files with the formatter
	@$(WEB) mix format
