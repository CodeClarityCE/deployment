# Shortcuts for the production stack; each is a plain `docker compose` command.
DOCKER_COMP = docker compose -f docker-compose.yaml

.DEFAULT_GOAL = help
.PHONY: help up down logs pull support-bundle knowledge-update

help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

up: ## Installs, upgrades or starts the stack
	@$(DOCKER_COMP) up -d

down: ## Stops the stack (keeps data and secrets)
	@$(DOCKER_COMP) down

logs: ## Display logs
	@$(DOCKER_COMP) logs --tail=0 --follow

pull: ## Pull images from docker hub
	@$(DOCKER_COMP) pull

knowledge-update: ## Runs a knowledge update now (ACTION=update-osv for OSV only)
	@$(DOCKER_COMP) run --rm service-knowledge ./plugin -knowledge -action $(or $(ACTION),update)

support-bundle: ## Writes a support bundle to attach to a bug report (OUT=<dir>, default here)
	@sh scripts/support-bundle.sh $(or $(OUT),.)
