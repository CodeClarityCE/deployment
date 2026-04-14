# Executables (local)
DOCKER_COMP = docker compose -f docker-compose.yaml

# Misc
.DEFAULT_GOAL = help
.PHONY        = help up down logs pull setup-tls setup-jwt setup-pg-certs restore-prod setup

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

setup: setup-tls setup-jwt setup-pg-certs ## Setup tls, jwt, and pg certs

setup-tls: ## Setup TLS
	@-mkdir -p certs
	@mkcert -cert-file certs/tls.pem -key-file certs/tls.key "localtest.io"

setup-jwt: ## Setup JWT
	@-mkdir -p jwt
	@openssl ecparam -name secp521r1 -genkey -noout -out jwt/private.pem
	@openssl ec -in jwt/private.pem -pubout -out jwt/public.pem

setup-pg-certs: ## Generate PostgreSQL SSL certificates
	@sh scripts/generate-pg-certs.sh certs/postgres

## —— Commands to dump and restore database 💾 ———————————————————————————————————————————————————————————————
download-dumps: ## Downloads the database dump
	@sh scripts/download-dumps.sh

restore-database: ## Restores the database
	@cd scripts && sh restore-db.sh codeclarity
	@cd scripts && sh restore-db.sh knowledge
	@cd scripts && sh restore-db.sh config