##@ Development (Phoenix + Postgres, in Docker)
.PHONY: dev.up dev.up.build dev.down dev.logs dev.shell db.migrate db.reset

dev.up: ## Start the stack (db + phoenix) on http://localhost:$(WEB_PORT)
	@$(DC) up -d

dev.up.build: ## Rebuild images and start
	@$(DC) up -d --build

dev.down: ## Stop the stack
	@$(DC) down

dev.logs: ## Follow the web logs
	@$(DC) logs -f web

dev.shell: ## IEx console in the running web container
	@$(WEB) iex -S mix

db.migrate: ## Run pending migrations
	@$(WEB) mix ecto.migrate

db.reset: ## Drop volumes and rebuild the database from scratch
	@$(DC) down -v
	@$(DC) up -d
