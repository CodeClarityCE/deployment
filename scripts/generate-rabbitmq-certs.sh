#!/bin/bash
# Generate a RabbitMQ server certificate for AMQP TLS connections.
# Reuses the existing PostgreSQL CA so clients verify both services with the same ca.crt.
# Server cert: 1 year (per modern TLS best practices)
set -e

RABBITMQ_CERT_DIR="${1:-./certs/rabbitmq}"
PG_CERT_DIR="${2:-./certs/postgres}"
SERVER_DAYS="${3:-365}"

# Ensure the shared CA exists (it is produced by generate-pg-certs.sh).
if [ ! -f "$PG_CERT_DIR/ca.crt" ] || [ ! -f "$PG_CERT_DIR/ca.key" ]; then
  echo "Shared CA not found in $PG_CERT_DIR — generating it first..."
  sh "$(dirname "$0")/generate-pg-certs.sh" "$PG_CERT_DIR"
fi

mkdir -p "$RABBITMQ_CERT_DIR"

echo "Generating RabbitMQ certificate in $RABBITMQ_CERT_DIR (signed by $PG_CERT_DIR/ca.crt)..."

# Generate server key and CSR
openssl req -new -nodes -text \
  -subj "/CN=rabbitmq" \
  -keyout "$RABBITMQ_CERT_DIR/server.key" \
  -out "$RABBITMQ_CERT_DIR/server.csr" 2>/dev/null

# Sign server certificate with the shared CA (include SANs for modern TLS verification).
# rabbitmq = compose service name, codeclarity = prod compose hostname.
SAN_EXT=$(mktemp)
printf "subjectAltName=DNS:rabbitmq,DNS:codeclarity,DNS:localhost,IP:127.0.0.1\n" > "$SAN_EXT"
openssl x509 -req -days "$SERVER_DAYS" -text \
  -in "$RABBITMQ_CERT_DIR/server.csr" \
  -CA "$PG_CERT_DIR/ca.crt" \
  -CAkey "$PG_CERT_DIR/ca.key" \
  -CAcreateserial \
  -extfile "$SAN_EXT" \
  -out "$RABBITMQ_CERT_DIR/server.crt" 2>/dev/null
rm -f "$SAN_EXT"

# Copy the CA alongside so the RabbitMQ container can mount a single certs dir.
cp "$PG_CERT_DIR/ca.crt" "$RABBITMQ_CERT_DIR/ca.crt"

# RabbitMQ requires the key to be readable by the rabbitmq user; keep it restrictive.
chmod 600 "$RABBITMQ_CERT_DIR/server.key"
chmod 644 "$RABBITMQ_CERT_DIR/server.crt" "$RABBITMQ_CERT_DIR/ca.crt"

# Clean up intermediate files
rm -f "$RABBITMQ_CERT_DIR/server.csr" "$PG_CERT_DIR/ca.srl"

echo "RabbitMQ certificate generated successfully:"
echo "  CA certificate:     $RABBITMQ_CERT_DIR/ca.crt (shared with PostgreSQL)"
echo "  Server certificate: $RABBITMQ_CERT_DIR/server.crt ($SERVER_DAYS days)"
echo "  Server key:         $RABBITMQ_CERT_DIR/server.key"
