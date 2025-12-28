#!/bin/bash

# Color codes for better output (using printf for portability)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Helper function for formatted output using printf for cross-platform compatibility
print_header() {
    printf "\n${BLUE}${BOLD}=== %s ===${NC}\n" "$1"
}

print_success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

print_info() {
    printf "${BLUE}ℹ${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}✗${NC} %s\n" "$1"
}

print_progress() {
    printf "${YELLOW}⚡${NC} %s" "$1"
}

# Verify the presence of required commands
print_header "Checking Requirements"

if ! command -v curl &>/dev/null; then
    print_error "curl is not installed."
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    print_error "openssl is not installed."
    exit 1
fi

if ! command -v docker &>/dev/null || ! command -v docker compose &>/dev/null; then
    print_error "docker or docker compose is not installed."
    exit 1
fi

print_success "All required commands are installed"

# Repository check
print_header "Repository Setup"
if [ -f ".git" ] || [ -d ".git" ]; then
    print_info "Git repository found. Skipping clone."
else
    print_progress "Cloning repository..."
    git clone https://github.com/CodeClarityCE/deployment.git >/dev/null 2>&1
    cd deployment
    printf "\r"
    print_success "Repository cloned"
fi

# Certificate generation
print_header "JWT Certificate Setup"
if [ ! -f jwt/private.pem ] && [ ! -f jwt/public.pem ]; then
    print_progress "Generating JWT certificates..."
    mkdir -p jwt
    openssl ecparam -name secp521r1 -genkey -noout -out jwt/private.pem 2>/dev/null
    openssl ec -in jwt/private.pem -pubout -out jwt/public.pem 2>/dev/null
    printf "\r"
    print_success "JWT certificates generated"
else
    print_info "JWT certificates already exist"
fi

# File permissions on Linux
if [[ "$OSTYPE" == "linux"* ]]; then
    chmod 711 jwt
    chmod 744 jwt/*
    print_info "File permissions set for Linux"
fi

# Domain configuration
print_header "Domain Configuration"
read -p "Is this installation running on localhost (Y/n)? " local_install

domain_name="localhost"
if [[ "$local_install" == "n" || "$local_install" == "N" ]]; then
    read -p "Enter the domain name (localtest.io): " domain_name
    print_info "Configuring for domain: $domain_name"
    
    sed -i.bak "s/WEB_HOST=https:\/\/localhost/WEB_HOST=https:\/\/$domain_name/" .env.api
    sed -i.bak "s/SERVER_NAME=localhost/SERVER_NAME=$domain_name/" .env.frontend
    
    read -p "Do you want Caddy to generate certificates (Y/n)? " caddy_generate_certs
    
    if [[ "$caddy_generate_certs" == "n" || "$caddy_generate_certs" == "N" ]]; then
        print_progress "Generating self-signed certificates..."
        mkdir -p certs
        openssl req -x509 -newkey rsa:4096 -keyout certs/tls.key -out certs/tls.pem -days 365 -nodes -subj "/CN=$domain_name" >/dev/null 2>&1
        sed -i.bak 's/# - .\/certs:\/etc\/caddy\/certs:ro/- .\/certs:\/etc\/caddy\/certs:ro/' docker-compose.yaml
        sed -i.bak 's/# CADDY_SERVER_EXTRA_DIRECTIVES=/CADDY_SERVER_EXTRA_DIRECTIVES=/' .env.frontend
        printf "\r"
        print_success "Self-signed certificates generated"
    else
        print_info "Caddy will generate certificates automatically"
    fi
else
    print_info "Configuring for localhost"
fi

# Database setup
print_header "Database Setup"

# Stop all running containers
print_progress "Stopping any running containers..."
docker compose -f docker-compose.yaml down >/dev/null 2>&1
printf "\r"
print_success "Containers stopped                    "

# Start DB container
print_progress "Starting database container..."
docker compose -f docker-compose.yaml up db -d >/dev/null 2>&1
printf "\r"
print_success "Database container started             "

# Wait for database to be ready
print_progress "Waiting for database to be ready"
counter=0
until docker compose -f docker-compose.yaml exec -T db pg_isready -U postgres >/dev/null 2>&1; do
    counter=$((counter + 1))
    if [ $counter -eq 30 ]; then
        printf "\n"
        print_error "Database failed to start after 30 seconds"
        exit 1
    fi
    printf "."
    sleep 1
done
printf "\r"
print_success "Database is ready                      "

# Ensure database dumps are available (stored in Git, knowledge.dump via LFS)
print_header "Checking Database Dumps"

print_progress "Verifying database dumps..."
if [ ! -s dump/knowledge.dump ] || [ $(wc -c < dump/knowledge.dump) -lt 1000 ]; then
    print_progress "Pulling knowledge.dump from Git LFS..."
    git lfs pull --include="dump/knowledge.dump"
fi
printf "\r"
print_success "Database dumps available               "

# Create databases
print_header "Creating Databases"
print_progress "Creating databases (this may take a moment)..."
docker compose -f docker-compose.yaml run --rm service-knowledge -knowledge -action setup
printf "\r"
print_success "Databases created successfully                "

# Restore database content
print_header "Restoring Database Content"
for db in "codeclarity" "knowledge" "config"; do
    print_progress "Restoring $db database..."
    docker compose -f docker-compose.yaml exec -T db sh -c "pg_restore -l /dump/$db.dump > /dump/$db.list && pg_restore -U postgres -d $db -L /dump/$db.list /dump/$db.dump" 2>/dev/null
    printf "\r"
    print_success "$db database restored                 "
done

# Start all containers
print_header "Starting Services"
print_progress "Starting all containers (this may take a moment)..."
docker compose -f docker-compose.yaml up -d >/dev/null 2>&1

# Wait a moment for services to stabilize
sleep 2

# Check if main services are running
if docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "api"; then
    printf "\r"
    print_success "All services started successfully                     "
else
    printf "\r"
    printf "${YELLOW}⚠${NC} %s\n" "Some services may still be starting"
fi

# Final message
print_header "Installation Complete"
printf "${GREEN}${BOLD}Success!${NC} CodeClarity is now running.\n"
printf "\n"
printf "📌 ${BOLD}Access URL:${NC} ${BLUE}https://%s:443${NC}\n" "$domain_name"
printf "📧 ${BOLD}Default login:${NC} john.doe@codeclarity.io\n"
printf "🔐 ${BOLD}Default password:${NC} ThisIs4Str0ngP4ssW0rd?\n"
printf "\n"
printf "${YELLOW}ℹ${NC} First login may take a moment while services initialize.\n"
printf "${YELLOW}ℹ${NC} Use 'docker compose logs -f' to monitor service logs.\n"