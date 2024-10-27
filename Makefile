# Executables (local)
DOCKER_COMP = docker compose

# Misc
.DEFAULT_GOAL = help
.PHONY        = help up down logs pull setup-tls setup-jwt knowledge-update knowledge-setup restore-prod setup

# Docker containers
CONT = $(DOCKER_COMP) exec results_db

# Executables
TAR = $(CONT) tar


## —— 🐳 The PHP pipeline Makefile 🐳 ——————————————————————————————————
help: ## Outputs this help screen
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}{printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}' | sed -e 's/\[32m##/[33m/'

## —— Docker 🐳 ————————————————————————————————————————————————————————————————
up: ## Starts the Docker images
	@$(DOCKER_COMP) -f docker-compose.yaml up -d

down: ## Stops the Docker images
	@$(DOCKER_COMP) -f docker-compose.yaml down

logs: ## Display logs
	@$(DOCKER_COMP) -f docker-compose.yaml logs --tail=0 --follow

pull: ## Pull images from docker hub
	@$(DOCKER_COMP) pull

setup: setup-tls setup-jwt knowledge-setup ## Setup tls and jwt

setup-tls: ## Setup TLS
	@-mkdir -p certs
	@mkcert -cert-file certs/tls.pem -key-file certs/tls.key "localtest.io"

setup-jwt: ## Setup JWT
	@-mkdir -p jwt
	@openssl ecparam -name secp521r1 -genkey -noout -out jwt/private.pem
	@openssl ec -in jwt/private.pem -pubout -out jwt/public.pem

knowledge-update: ## Create knowledge
	@$(DOCKER_COMP) -f docker-compose.knowledge.yaml run --rm knowledge -knowledge -action update

knowledge-setup: ## Setup knowledge
	@$(DOCKER_COMP) -f docker-compose.knowledge.yaml run --rm knowledge -knowledge -action setup