#!/bin/sh
# Writes a support bundle to attach to a bug report: component versions, the configuration with
# secrets redacted, recent error logs per service and recent error reports from the web app.
# Run it in the directory that holds docker-compose.yaml; `make support-bundle` does.
# Usage: sh support-bundle.sh [out dir]   (default: the current directory)
# Env: SUPPORT_BUNDLE_SINCE (default 24h), SUPPORT_BUNDLE_LINES (default 200 per log).
# Needs only docker, awk, sed, grep and tar on the host. Prints the archive's path last.
set -eu

SINCE=${SUPPORT_BUNDLE_SINCE:-24h}
LINES=${SUPPORT_BUNDLE_LINES:-200}
# Names whose values are treated as secrets, wherever they appear as KEY=value or key: value.
SENSITIVE='password|passwd|secret|token|key|auth|credential|cookie|private'

fail() {
	echo "support-bundle: $*" >&2
	exit 1
}

[ -f docker-compose.yaml ] || fail "no docker-compose.yaml in $(pwd); run it in the deployment directory"
out=${1:-.}
mkdir -p "$out"
out=$(cd "$out" && pwd)

# The bundle and the secret values read to redact it are readable by this user only.
umask 077
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
name=codeclarity-support-$(date -u +%Y%m%dT%H%M%SZ)
b="$tmp/$name"
mkdir -p "$b/logs"

# Prints each line's value: KEY=value lines lose the name and surrounding quotes, others stay.
values() {
	sed -e 's/^[A-Za-z_][A-Za-z0-9_]*=//' -e "s/^'\\(.*\\)'\$/\\1/" -e 's/^"\(.*\)"$/\1/'
}

# Known secret values, one per line: the secrets volume, then secret-named settings in .env and the environment.
known="$tmp/known"
if docker compose run --rm --no-deps -T --entrypoint sh generate-secrets -c \
	"find /secrets -type f ! -name '*.crt' ! -name '*public*' ! -name '*.json' ! -name '*_salt' ! -name '*.tmp' -exec cat {} +" \
	>"$tmp/volume" 2>"$tmp/volume.err"; then
	values <"$tmp/volume" >"$known"
else
	: >"$known"
	echo "support-bundle: cannot read the secrets volume ($(tail -n 1 "$tmp/volume.err")); secrets are redacted by name only" >&2
fi
{
	if [ -f .env ]; then grep -Ei "^[A-Za-z0-9_]*($SENSITIVE)[A-Za-z0-9_]*=" .env || :; fi
	env | grep -Ei "^[A-Za-z0-9_]*($SENSITIVE)[A-Za-z0-9_]*=" || :
} | values >>"$known"
# Short lines and PEM armour are not worth matching on their own.
awk 'length($0) >= 8 && $0 !~ /^-----/' "$known" | sort -u >"$known.long"
rm -f "$tmp/volume" "$known"

# Copies stdin to stdout with known secret values, secret-named values, private keys and
# passwords in URLs replaced by [REDACTED].
redact() {
	awk -v known="$known.long" -v sensitive="$SENSITIVE" '
	BEGIN { while ((getline s < known) > 0) secret[++n] = s }
	function scrub(line,   i, p, done) {
		for (i = 1; i <= n; i++) {
			done = ""
			while ((p = index(line, secret[i])) > 0) {
				done = done substr(line, 1, p - 1) "[REDACTED]"
				line = substr(line, p + length(secret[i]))
			}
			line = done line
		}
		return line
	}
	# Lines inside a private key block are dropped; the block becomes one marker.
	inkey { if ($0 ~ /-----END [A-Z0-9 ]*PRIVATE KEY-----/) inkey = 0; next }
	/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/ && !/-----END [A-Z0-9 ]*PRIVATE KEY-----/ {
		inkey = 1
		match($0, /^[ \t]*/)
		print substr($0, 1, RLENGTH) "[REDACTED PRIVATE KEY]"
		next
	}
	{
		line = scrub($0)
		gsub(/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*-----END [A-Z0-9 ]*PRIVATE KEY-----/, "[REDACTED PRIVATE KEY]", line)
		if (match(line, /^[ \t]*-?[ \t]*"?[A-Za-z0-9_.-]+"?[ \t]*[:=]/)) {
			head = substr(line, 1, RLENGTH)
			value = substr(line, RLENGTH + 1)
			key = head
			gsub(/[^A-Za-z0-9_.-]/, "", key)
			# Empty values stay, so the bundle still shows a secret is not set.
			if (tolower(key) ~ sensitive && value !~ /^[ \t]*(""|\047\047)?[ \t]*$/)
				line = head (head ~ /=$/ ? "" : " ") "[REDACTED]"
		}
		print line
	}' | sed -E 's#(://[^:/@[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g'
}

{
	echo "CodeClarity support bundle, written $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "Release of docker-compose.yaml: $(sed -n 's/^x-release-version: &release-version "\(.*\)"$/\1/p' docker-compose.yaml)"
	# Compose prefers the environment over .env, and so does this.
	version=${CODECLARITY_VERSION:-}
	if [ -z "$version" ] && [ -f .env ]; then version=$(sed -n 's/^CODECLARITY_VERSION=//p' .env); fi
	echo "CODECLARITY_VERSION: $version"
	echo "Docker Engine: $(docker version --format '{{.Server.Version}}' 2>&1 || :)"
	echo "Docker Compose: $(docker compose version --short 2>&1 || :)"
	echo "Host: $(uname -srm)"
	echo
	echo "Images:"
	docker compose images 2>&1 || :
} | redact >"$b/versions.txt"

docker compose ps -a 2>&1 | redact >"$b/containers.txt" || :
docker compose config 2>&1 | redact >"$b/config.yaml" || :

# Error and fatal lines of each service's recent logs, in the formats the stack's images write.
docker compose ps -a --format '{{.Service}}' 2>/dev/null | sort -u >"$tmp/services" || :
while IFS= read -r service; do
	docker compose logs --no-color --no-log-prefix --timestamps --since "$SINCE" "$service" </dev/null 2>&1 |
		grep -E -e '"level": ?"(error|fatal|panic)"' -e 'level=(error|fatal|panic)' -e 'ERROR|FATAL|PANIC' \
			-e '\[(error|critical)\]' -e '^panic:' | tail -n "$LINES" | redact >"$b/logs/$service.log" || :
done <"$tmp/services"

# Error reports: what the web app sent to the API, which logs them with source "frontend".
docker compose logs --no-color --no-log-prefix --timestamps --since "$SINCE" api 2>/dev/null |
	grep -F '"source":"frontend"' | tail -n "$LINES" | redact >"$b/error-reports.log" || :

cat >"$b/README.txt" <<EOF
CodeClarity support bundle. Look it over before you attach it to a bug report.

versions.txt       release, image versions, Docker and host
containers.txt     every container and its state
config.yaml        the resolved Compose configuration
logs/<service>.log error lines of the last $SINCE, at most $LINES per service
error-reports.log  error reports the web app sent in the last $SINCE, at most $LINES

Generated secrets, secret-named settings, private keys and passwords in URLs are
replaced by [REDACTED]. Values you typed into analyses or project names are not.
EOF

# A last check that no known secret value is left; on a match, nothing is written.
if [ -s "$known.long" ] && grep -rqF -f "$known.long" "$b"; then
	fail "a secret value is still in the bundle, so none was written; please report this"
fi

tar -czf "$out/$name.tar.gz" -C "$tmp" "$name"
echo "support-bundle: look it over before attaching it to a bug report. Written to:" >&2
echo "$out/$name.tar.gz"
