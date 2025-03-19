#!/bin/bash

# Verify the presence of required commands
if ! command -v curl &>/dev/null; then
    echo "Error: curl is not installed."
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    echo "Error: openssl is not installed."
    exit 1
fi

if ! command -v make &>/dev/null; then
    echo "Error: make is not installed."
    exit 1
fi

if ! command -v docker &>/dev/null || ! command -v docker-compose &>/dev/null; then
    echo "Error: docker or docker-compose is not installed."
    exit 1
fi

echo "All required commands are installed."

git clone git@github.com:CodeClarityCE/deployment.git
cd deployment

# openssl needs to be installed
make setup-jwt

read -p "Is this installation local (y/n)? " local_install

domain_name="localhost"
if [[ "$local_install" == "y" || "$local_install" == "Y" ]]; then
    echo "Running local installation."
else
    read -p "Enter the domain name (localtest.io): " domain_name
    echo "Running installation for domain: $domain_name"
    sed -i '' "s/WEB_HOST=https:\/\/localhost/WEB_HOST=https:\/\/$domain_name/" .env.api
    sed -i '' "s/SERVER_NAME=localhost/SERVER_NAME=$domain_name/" .env.frontend
    read -p "Do you want Caddy to generate certificates (y/n)? " caddy_generate_certs

    if [[ "$caddy_generate_certs" == "y" || "$caddy_generate_certs" == "Y" ]]; then
        echo "Letting Caddy generate certificates..."
        # Caddy will handle certificate generation automatically
    else
        echo "Generating self-signed certificates..."
        mkdir -p certs
        openssl req -x509 -newkey rsa:4096 -keyout certs/tls.key -out certs/tls.pem -days 365 -nodes -subj "/CN=$domain_name"
        sed -i '' 's/# - .\/certs:\/etc\/caddy\/certs:ro/- .\/certs:\/etc\/caddy\/certs:ro/' docker-compose.yaml
        sed -i '' 's/# CADDY_SERVER_EXTRA_DIRECTIVES=/CADDY_SERVER_EXTRA_DIRECTIVES=/' .env.frontend
    fi
fi

# curl and docker compose need to be installed
make up
make download-dumps
make knowledge-setup
make restore-database
make down && make up

echo "Installation successful, you can now visit: https://$domain_name:443"
