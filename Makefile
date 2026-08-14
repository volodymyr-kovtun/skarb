# Skarb — one command for everything.
# Run `make` (or `make help`) to see what's available.

BACKEND_DIR  := backend/Skarb.Api
FRONTEND_DIR := frontend
APP_URL      := http://localhost:5178
DB_CONTAINER := skarb-postgres

.DEFAULT_GOAL := help

# ---------------------------------------------------------------- meta

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  Skarb — make targets"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ---------------------------------------------------------------- dependencies

.PHONY: deps-up
deps-up: ## Start dependencies (PostgreSQL 17 in Docker)
	docker compose up -d --wait

.PHONY: deps-down
deps-down: ## Stop dependencies (data is kept)
	docker compose down

.PHONY: deps-reset
deps-reset: ## DESTROY the database and start fresh
	docker compose down -v
	docker compose up -d --wait

.PHONY: install
install: ## Restore backend packages + install frontend node modules
	dotnet restore $(BACKEND_DIR)
	cd $(FRONTEND_DIR) && npm install

# ---------------------------------------------------------------- run

.PHONY: run
run: deps-up frontend ## Run the full app (builds SPA, serves everything on :5178)
	cd $(BACKEND_DIR) && dotnet run

.PHONY: dev
dev: deps-up ## Dev mode: API on :5178 + Vite hot reload on :5173 (Ctrl+C stops both)
	@trap 'kill 0' INT TERM; \
	( cd $(BACKEND_DIR) && dotnet run ) & \
	( cd $(FRONTEND_DIR) && npm run dev ) & \
	wait

.PHONY: dev-api
dev-api: deps-up ## Dev mode: backend only (:5178)
	cd $(BACKEND_DIR) && dotnet run

.PHONY: dev-web
dev-web: ## Dev mode: frontend only (:5173, expects API on :5178)
	cd $(FRONTEND_DIR) && npm run dev

# ---------------------------------------------------------------- build & check

.PHONY: build
build: backend frontend ## Build backend + frontend

.PHONY: backend
backend: ## Build the .NET backend
	dotnet build $(BACKEND_DIR) -v q

.PHONY: frontend
frontend: ## Build the SPA into the backend's wwwroot
	cd $(FRONTEND_DIR) && npm run build

.PHONY: check
check: ## Typecheck frontend + build backend (CI-style sanity check)
	cd $(FRONTEND_DIR) && npx tsc -b
	dotnet build $(BACKEND_DIR) -v q

# ---------------------------------------------------------------- database

.PHONY: migrate
migrate: ## Create an EF migration: make migrate NAME=AddSomething
ifndef NAME
	$(error Usage: make migrate NAME=AddSomething)
endif
	cd $(BACKEND_DIR) && dotnet ef migrations add $(NAME)

.PHONY: db-shell
db-shell: ## Open a psql shell in the database
	docker exec -it $(DB_CONTAINER) psql -U skarb -d skarb

.PHONY: db-logs
db-logs: ## Tail PostgreSQL logs
	docker logs -f $(DB_CONTAINER)

# ---------------------------------------------------------------- misc

.PHONY: open
open: ## Open the app in the browser
	open $(APP_URL)

.PHONY: clean
clean: ## Remove build artifacts (bin/obj, built SPA)
	rm -rf $(BACKEND_DIR)/bin $(BACKEND_DIR)/obj $(BACKEND_DIR)/wwwroot
	rm -rf $(FRONTEND_DIR)/node_modules/.vite
