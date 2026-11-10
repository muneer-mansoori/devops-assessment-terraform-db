.PHONY: help up down reset logs psql backup restore explain e2e tf-fmt tf-plan-dev tf-plan-prod tf-plan

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

up: ## Start PostgreSQL (migrations + seed on first start)
	docker compose up -d --wait

down: ## Stop the database, keep data
	docker compose down

reset: ## Destroy the database volume and start fresh
	docker compose down -v && docker compose up -d --wait

logs: ## Follow database logs
	docker compose logs -f db

psql: ## Open psql in the source database
	docker compose exec db psql -U hotel -d hotel_db

backup: ## Timestamped, verified backup into backups/
	./scripts/backup.sh

restore: ## Restore newest backup into a fresh database and verify it
	./scripts/restore.sh

explain: ## Report query plan before/after the index
	./scripts/explain.sh

e2e: ## Full database check from a clean slate (removes local volume)
	./scripts/e2e.sh

tf-fmt: ## Format all Terraform
	terraform -chdir=infra fmt -recursive

tf-plan-dev: ## Offline fmt/init/validate/plan for dev
	./scripts/tf-plan-offline.sh dev

tf-plan-prod: ## Offline fmt/init/validate/plan for prod
	./scripts/tf-plan-offline.sh prod

tf-plan: tf-plan-dev tf-plan-prod ## Both environments
