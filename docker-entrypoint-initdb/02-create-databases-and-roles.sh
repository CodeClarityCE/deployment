#!/bin/bash
set -e

# Create databases and revoke default PUBLIC connect privilege
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE codeclarity;
    CREATE DATABASE knowledge;
    CREATE DATABASE plugins;
    CREATE DATABASE config;
    REVOKE CONNECT ON DATABASE codeclarity FROM PUBLIC;
    REVOKE CONNECT ON DATABASE knowledge FROM PUBLIC;
    REVOKE CONNECT ON DATABASE plugins FROM PUBLIC;
    REVOKE CONNECT ON DATABASE config FROM PUBLIC;
EOSQL

# Create uuid-ossp extension in each database
for db in codeclarity knowledge plugins config; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
done

# Create application roles with least-privilege access
# Passwords use env vars set in .env.database, with fallback to POSTGRES_PASSWORD
# Uses psql -v variable binding (:'var') to avoid SQL injection from passwords
CC_API_PASSWORD="${CC_API_PASSWORD:-$POSTGRES_PASSWORD}"
CC_SERVICE_PASSWORD="${CC_SERVICE_PASSWORD:-$POSTGRES_PASSWORD}"
CC_PLUGIN_PASSWORD="${CC_PLUGIN_PASSWORD:-$POSTGRES_PASSWORD}"
CC_KNOWLEDGE_PASSWORD="${CC_KNOWLEDGE_PASSWORD:-$POSTGRES_PASSWORD}"
CC_EXPORTER_PASSWORD="${CC_EXPORTER_PASSWORD:-$POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v api_pass="$CC_API_PASSWORD" \
  -v service_pass="$CC_SERVICE_PASSWORD" \
  -v plugin_pass="$CC_PLUGIN_PASSWORD" \
  -v knowledge_pass="$CC_KNOWLEDGE_PASSWORD" \
  -v exporter_pass="$CC_EXPORTER_PASSWORD" <<-'EOSQL'
    -- API role: read/write on codeclarity, read on knowledge, read/write on plugins/config
    CREATE ROLE cc_api LOGIN PASSWORD :'api_pass';

    -- Service role: used by dispatcher, downloader, notifier, scheduler, follower
    CREATE ROLE cc_service LOGIN PASSWORD :'service_pass';

    -- Plugin role: used by analysis plugins (js-sbom, vuln-finder, etc.)
    CREATE ROLE cc_plugin LOGIN PASSWORD :'plugin_pass';

    -- Knowledge role: used by the knowledge service for mirror updates
    CREATE ROLE cc_knowledge LOGIN PASSWORD :'knowledge_pass';

    -- Exporter role: read-only for monitoring
    CREATE ROLE cc_exporter LOGIN PASSWORD :'exporter_pass';
    GRANT pg_read_all_stats TO cc_exporter;

    -- CONNECT privileges per database
    GRANT CONNECT ON DATABASE codeclarity TO cc_api, cc_service, cc_plugin, cc_exporter;
    GRANT CONNECT ON DATABASE knowledge TO cc_api, cc_service, cc_plugin, cc_knowledge;
    GRANT CONNECT ON DATABASE plugins TO cc_api, cc_service, cc_plugin, cc_knowledge;
    GRANT CONNECT ON DATABASE config TO cc_api, cc_service, cc_plugin, cc_knowledge;
EOSQL

# Grant table-level permissions on codeclarity database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "codeclarity" <<-EOSQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE, CREATE ON SCHEMA public TO cc_api, cc_service;
    GRANT USAGE ON SCHEMA public TO cc_plugin;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO cc_api, cc_service;
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO cc_plugin;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cc_api, cc_service, cc_plugin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cc_api, cc_service;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO cc_plugin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cc_api, cc_service, cc_plugin;
EOSQL

# Grant table-level permissions on knowledge database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "knowledge" <<-EOSQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE, CREATE ON SCHEMA public TO cc_api, cc_service, cc_plugin, cc_knowledge;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO cc_api, cc_service, cc_plugin;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO cc_knowledge;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO cc_api, cc_service, cc_plugin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cc_knowledge;
EOSQL

# Grant table-level permissions on plugins database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "plugins" <<-EOSQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE, CREATE ON SCHEMA public TO cc_api, cc_service, cc_plugin, cc_knowledge;
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO cc_api, cc_service, cc_plugin, cc_knowledge;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cc_api, cc_service, cc_plugin, cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO cc_api, cc_service, cc_plugin, cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cc_api, cc_service, cc_plugin, cc_knowledge;
EOSQL

# Grant table-level permissions on config database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "config" <<-EOSQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    GRANT USAGE, CREATE ON SCHEMA public TO cc_api, cc_service, cc_knowledge;
    GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO cc_api, cc_service, cc_knowledge;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cc_api, cc_service, cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO cc_api, cc_service, cc_knowledge;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cc_api, cc_service, cc_knowledge;
EOSQL

echo "Database roles and permissions configured successfully."
