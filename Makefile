# Executables (local)
DOCKER_COMP = docker compose -f docker-compose.yaml
DOCKER_COMP_WITH_KNOWLEDGE = docker compose -f docker-compose.yaml -f docker-compose.knowledge.yaml

# Misc
.DEFAULT_GOAL = help
.PHONY        = help up down logs pull setup-tls setup-jwt knowledge-update knowledge-setup knowledge-daemon-up knowledge-daemon-down restore-prod setup

# Docker containers
CONT = $(DOCKER_COMP) exec results_db

# Executables
TAR = $(CONT) tar


## —— 🐳 The PHP pipeline Makefile 🐳 ——————————————————————————————————
help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

## —— Docker 🐳 ————————————————————————————————————————————————————————————————
up: ## Starts the Docker images
	@$(DOCKER_COMP) up -d

down: ## Stops the Docker images
	@$(DOCKER_COMP) down

logs: ## Display logs
	@$(DOCKER_COMP) logs --tail=0 --follow

pull: ## Pull images from docker hub
	@$(DOCKER_COMP) pull

save: ## Save images on disk
	@sh scripts/image-save.sh

load: ## Load saved images
	@docker load < services.img

setup: setup-tls setup-jwt knowledge-setup ## Setup tls and jwt

setup-tls: ## Setup TLS
	@-mkdir -p certs
	@mkcert -cert-file certs/tls.pem -key-file certs/tls.key "localtest.io"

setup-jwt: ## Setup JWT
	@-mkdir -p jwt
	@openssl ecparam -name secp521r1 -genkey -noout -out jwt/private.pem
	@openssl ec -in jwt/private.pem -pubout -out jwt/public.pem

knowledge-update: ## Run one-time knowledge update
	@$(DOCKER_COMP) -f docker-compose.knowledge.yaml run --rm knowledge -knowledge -action update

knowledge-setup: ## Run one-time knowledge setup
	@$(DOCKER_COMP) -f docker-compose.knowledge.yaml run --rm knowledge -knowledge -action setup

knowledge-daemon-up: ## Start knowledge daemon (runs updates every 6 hours) - requires knowledge-setup first
	@$(DOCKER_COMP_WITH_KNOWLEDGE) up -d

knowledge-daemon-down: ## Stop knowledge daemon
	@$(DOCKER_COMP_WITH_KNOWLEDGE) down

## —— Commands to dump and restore database 💾 ———————————————————————————————————————————————————————————————
download-dumps: ## Downloads the database dump
	@sh scripts/download-dumps.sh

restore-database: ## Restores the database
	@cd scripts && sh restore-db.sh codeclarity
	@cd scripts && sh restore-db.sh knowledge
	@cd scripts && sh restore-db.sh config