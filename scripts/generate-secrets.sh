#!/bin/sh
# The secrets setup job: generates each instance secret once into a store and never overwrites
# one that exists, then lays out, per service, the files that service reads.
# Usage: sh generate-secrets.sh [dir]   (default /secrets; needs openssl, run as root)
# Env: RABBITMQ_DEFINITIONS, the static RabbitMQ definitions copied into its view.
#
# <dir>/.store holds the secrets themselves. Each other directory is one service's view, mounted
# alone into that service, and is rebuilt from the store on every run.
set -eu

dir=${1:-/secrets}
store="$dir/.store"
# Postgres (and pgbouncer) run as uid 70 in their Alpine images and need to own their key.
PG_UID=70
# RabbitMQ runs as rabbitmq (uid 100, gid 101) in its Alpine image.
RABBITMQ_OWNER=100:101
RABBITMQ_DEFINITIONS=${RABBITMQ_DEFINITIONS:-/etc/codeclarity/rabbitmq-definitions.json}
DAYS=3650

fail() {
	echo "generate-secrets: $*" >&2
	exit 1
}

umask 077
mkdir -p "$store"
chmod 700 "$store"

# Runs "$2 <tmp file>" to make store file $1 when it is missing, then moves it into place,
# so an interrupted run never leaves a half-written secret behind.
once() {
	[ -s "$store/$1" ] && return 0
	tmp="$store/.$1.tmp"
	rm -f "$tmp"
	"$2" "$tmp" || {
		rm -f "$tmp"
		fail "cannot generate $1"
	}
	mv "$tmp" "$store/$1"
	echo "generate-secrets: generated $1"
}

salt() {
	openssl rand 4 >"$1"
}

password() {
	openssl rand -hex 32 >"$1"
}

ec_key() {
	openssl ecparam -name secp521r1 -genkey -noout -out "$1" 2>/dev/null
}

rsa_key() {
	openssl genrsa -out "$1" 2048 2>/dev/null
}

ca_cert() {
	openssl req -new -x509 -days "$DAYS" -key "$store/ca.key" -subj "/CN=CodeClarity internal CA" \
		-addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
		-out "$1" 2>/dev/null
}

# Signs a server certificate for key $2 named $3 with subject alternative names $4.
server_cert() {
	ext="$store/.ext"
	printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$4" >"$ext"
	openssl req -new -key "$store/$2" -subj "/CN=$3" 2>/dev/null |
		openssl x509 -req -days "$DAYS" -CA "$store/ca.crt" -CAkey "$store/ca.key" \
			-set_serial "0x$(openssl rand -hex 16)" -extfile "$ext" -out "$1" 2>/dev/null
	status=$?
	rm -f "$ext"
	return $status
}

postgres_cert() { server_cert "$1" postgres.key db "DNS:db,DNS:pgbouncer,DNS:localhost,IP:127.0.0.1"; }
rabbitmq_cert() { server_cert "$1" rabbitmq.key rabbitmq "DNS:rabbitmq,DNS:codeclarity,DNS:localhost,IP:127.0.0.1"; }
jwt_public() { openssl ec -in "$store/jwt_private.pem" -pubout -out "$1" 2>/dev/null; }

for name in postgres cc_api cc_service cc_follower cc_plugin cc_knowledge cc_exporter pgbouncer_auth \
	rabbitmq cookie_secret grafana_admin; do
	once "${name}_password" password
done
once rabbitmq_salt salt
once ca.key rsa_key
once ca.crt ca_cert
once postgres.key rsa_key
once postgres.crt postgres_cert
once rabbitmq.key rsa_key
once rabbitmq.crt rabbitmq_cert
once jwt_private.pem ec_key
once jwt_public.pem jwt_public

secret() {
	cat "$store/$1_password"
}

# Views. Each file is written beside its target and moved over it.
put() {
	mkdir -p "$(dirname "$dir/$1")"
	cat >"$dir/$1.tmp"
	chmod "${2:-444}" "$dir/$1.tmp"
	mv "$dir/$1.tmp" "$dir/$1"
}

copy() {
	put "$1" "${3:-444}" <"$store/$2"
}

# An env file of KEY='value' lines, read by `set -a; . file` and by dotenv alike.
env_file() {
	target=$1
	shift
	for pair; do
		printf "%s='%s'\n" "${pair%%=*}" "${pair#*=}"
	done | put "$target"
}

umask 022
for view in db pgbouncer rabbitmq knowledge-restore migrate api service follower plugin knowledge grafana exporter; do
	copy "$view/ca.crt" ca.crt
done

env_file db/env "POSTGRES_PASSWORD=$(secret postgres)" "CC_API_PASSWORD=$(secret cc_api)" \
	"CC_SERVICE_PASSWORD=$(secret cc_service)" "CC_FOLLOWER_PASSWORD=$(secret cc_follower)" \
	"CC_PLUGIN_PASSWORD=$(secret cc_plugin)" \
	"CC_KNOWLEDGE_PASSWORD=$(secret cc_knowledge)" "CC_EXPORTER_PASSWORD=$(secret cc_exporter)" \
	"PGBOUNCER_AUTH_PASSWORD=$(secret pgbouncer_auth)"
for view in db pgbouncer; do
	copy "$view/server.crt" postgres.crt
	copy "$view/server.key" postgres.key 600
	chown "$PG_UID:$PG_UID" "$dir/$view/server.key" "$dir/$view/server.crt" "$dir/$view/ca.crt"
done
printf '"pgbouncer_auth" "%s"\n' "$(secret pgbouncer_auth)" | put pgbouncer/userlist.txt 600
chown "$PG_UID:$PG_UID" "$dir/pgbouncer/userlist.txt"

# RabbitMQ skips its default user and vhost when it imports definitions, so they are declared here.
# The hash uses its sha256 scheme, base64 of salt then sha256(salt, password), with a stored salt.
rabbitmq_hash() {
	{
		cat "$store/rabbitmq_salt"
		printf '%s' "$(secret rabbitmq)" | cat "$store/rabbitmq_salt" - | openssl dgst -sha256 -binary
	} | openssl base64 -A
}
hash=$(rabbitmq_hash) || fail "cannot hash the RabbitMQ password"
put rabbitmq/definitions/00-users.json 440 <<EOF
{
  "vhosts": [{"name": "/"}],
  "users": [
    {
      "name": "codeclarity",
      "password_hash": "$hash",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["administrator"]
    }
  ],
  "permissions": [
    {"user": "codeclarity", "vhost": "/", "configure": ".*", "write": ".*", "read": ".*"}
  ]
}
EOF
chown "$RABBITMQ_OWNER" "$dir/rabbitmq/definitions/00-users.json"
[ -s "$RABBITMQ_DEFINITIONS" ] || fail "no RabbitMQ definitions at $RABBITMQ_DEFINITIONS"
put rabbitmq/definitions/10-dead-letter.json <"$RABBITMQ_DEFINITIONS"
rm -f "$dir/rabbitmq/env"
copy rabbitmq/server.crt rabbitmq.crt
copy rabbitmq/server.key rabbitmq.key 600
chown "$RABBITMQ_OWNER" "$dir/rabbitmq/server.key"

env_file knowledge-restore/env "POSTGRES_PASSWORD=$(secret postgres)"
# migrate creates the follower's role on an install the init script ran on before it existed.
env_file migrate/.env.prod "PG_DB_ADMIN_PASSWORD=$(secret postgres)" "PG_FOLLOWER_PASSWORD=$(secret cc_follower)"
env_file api/.env.prod "PG_DB_PASSWORD=$(secret cc_api)" "AMQP_PASSWORD=$(secret rabbitmq)" \
	"COOKIE_SECRET=$(secret cookie_secret)"
copy api-jwt/private.pem jwt_private.pem
copy api-jwt/public.pem jwt_public.pem
for role in service follower plugin knowledge; do
	env_file "$role/env" "PG_DB_PASSWORD=$(secret "cc_$role")" "AMQP_PASSWORD=$(secret rabbitmq)"
done
copy grafana/admin_password grafana_admin_password
copy grafana/cc_exporter_password cc_exporter_password
copy exporter/cc_exporter_password cc_exporter_password
echo "generate-secrets: secrets ready in $dir"
