#!/bin/bash
# Generate certificates for PostgreSQL TLS connections
# CA cert: 10 years, Server cert: 1 year (per PG 18 best practices)
set -e

CERT_DIR="${1:-./certs/postgres}"
SERVER_DAYS="${2:-365}"
mkdir -p "$CERT_DIR"

echo "Generating PostgreSQL certificates in $CERT_DIR..."

# Generate CA key and certificate (valid 10 years) with v3_ca extension
openssl req -new -x509 -days 3650 -nodes -text \
  -subj "/CN=CodeClarity-PG-CA" \
  -keyout "$CERT_DIR/ca.key" \
  -out "$CERT_DIR/ca.crt" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# Generate server key and CSR
openssl req -new -nodes -text \
  -subj "/CN=db" \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.csr" 2>/dev/null

# Sign server certificate with CA (include SANs for modern TLS verification)
# Use a temp file for the extension config (portable; process substitution requires bash)
SAN_EXT=$(mktemp)
printf "subjectAltName=DNS:db,DNS:localhost,IP:127.0.0.1\n" > "$SAN_EXT"
openssl x509 -req -days "$SERVER_DAYS" -text \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial \
  -extfile "$SAN_EXT" \
  -out "$CERT_DIR/server.crt" 2>/dev/null
rm -f "$SAN_EXT"

# PostgreSQL requires restrictive permissions on the private key
chmod 600 "$CERT_DIR/server.key"
chmod 600 "$CERT_DIR/ca.key"
chmod 644 "$CERT_DIR/server.crt" "$CERT_DIR/ca.crt"

# Clean up intermediate files
rm -f "$CERT_DIR/server.csr" "$CERT_DIR/ca.srl"

echo "PostgreSQL certificates generated successfully:"
echo "  CA certificate:     $CERT_DIR/ca.crt (10 years)"
echo "  Server certificate: $CERT_DIR/server.crt ($SERVER_DAYS days)"
echo "  Server key:         $CERT_DIR/server.key"
