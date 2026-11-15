# shellcheck shell=sh
# Verifies dumps against the knowledge dump manifest and restores them.
# Runs on a host or inside the db container (busybox sh). Manifest format: docs/knowledge-dump.md
# in codeclarity-dev.
#
# Usage:
#   sh restore-dump.sh verify
#   sh restore-dump.sh restore <dump> <database> [pg_restore options]
#   sh restore-dump.sh restore-if-empty   (verifies, then restores knowledge and config if knowledge has no tables)
# In the db container: sh -c "$(cat restore-dump.sh)" restore-dump <command> [args]
# Env: DUMP_DIR (default /dump). Restores use POSTGRES_PASSWORD as the postgres password (PGHOST for
# another host); restore-if-empty makes PG_KNOWLEDGE_ROLE (cc_knowledge) and PG_CONFIG_ROLE (cc_api) owners.
#
# Without knowledge-manifest.json (the dump layout before manifests), dumps restore unverified
# with a warning. Split dump parts (*.dump.part-*) are always refused: dumps ship whole.

set -u

DUMP_DIR=${DUMP_DIR:-/dump}
MANIFEST=knowledge-manifest.json
SUMS=knowledge-manifest.sha256

fail() {
	echo "restore-dump: $*" >&2
	exit 1
}

sha() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$@" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$@" | cut -d' ' -f1
	else
		fail "needs sha256sum or shasum"
	fi
}

has_manifest() {
	[ -f "$DUMP_DIR/$MANIFEST" ]
}

# Fails if any split dump part is present.
refuse_parts() {
	for part in "$DUMP_DIR"/*.dump.part-*; do
		[ -e "$part" ] && fail "${part##*/} is a split dump part; dumps ship whole, refusing to restore"
	done
	return 0
}

# Checks the manifest is one this script reads and that its checksum list is there.
check_manifest() {
	tr -d ' \t\r\n' <"$DUMP_DIR/$MANIFEST" | grep -q '^{"format":1,' ||
		fail "$MANIFEST is not manifest format 1, refusing to restore"
	[ -f "$DUMP_DIR/$SUMS" ] || fail "$MANIFEST has no $SUMS next to it, refusing to restore"
	if grep -v '^[0-9a-f]\{64\}  [A-Za-z0-9._-]*$' "$DUMP_DIR/$SUMS" | grep -q .; then
		fail "$SUMS has a malformed line, refusing to restore"
	fi
}

# Prints "<name> <sha256>" for each whole dump the manifest lists.
manifest_files() {
	tr -d ' \t\r\n' <"$DUMP_DIR/$MANIFEST" |
		grep -o '"name":"[A-Za-z0-9._-]*","database":"[A-Za-z0-9_]*","size":[0-9]*,"sha256":"[0-9a-f]\{64\}"' |
		sed 's/^"name":"\([^"]*\)".*"sha256":"\([0-9a-f]*\)"$/\1 \2/'
}

# Prints the manifest's SHA-256 of a dump, or nothing if it does not list it.
manifest_sha() {
	manifest_files | while read -r name whole; do
		[ "$name" = "$1" ] && echo "$whole"
	done
}

verify() {
	refuse_parts
	if ! has_manifest; then
		echo "restore-dump: warning, no $MANIFEST in $DUMP_DIR (old dump layout); dumps are not verified" >&2
		return 0
	fi
	check_manifest
	[ -n "$(manifest_files)" ] || fail "$MANIFEST lists no files, refusing to restore"

	bad=0
	while read -r want name; do
		if [ ! -f "$DUMP_DIR/$name" ]; then
			echo "restore-dump: $name: MISSING" >&2
			bad=1
		elif [ "$(sha "$DUMP_DIR/$name")" != "$want" ]; then
			echo "restore-dump: $name: FAILED, SHA-256 does not match $SUMS" >&2
			bad=1
		else
			echo "restore-dump: $name: OK"
		fi
	done <"$DUMP_DIR/$SUMS"

	files=$(manifest_files)
	while read -r name want; do
		if [ "$(grep "  $name\$" "$DUMP_DIR/$SUMS" | cut -d' ' -f1)" != "$want" ]; then
			echo "restore-dump: $name: FAILED, does not match the SHA-256 in $MANIFEST" >&2
			bad=1
		fi
	done <<EOF
$files
EOF

	[ "$bad" -eq 0 ] || fail "the dump set in $DUMP_DIR does not match its manifest, nothing was restored"
	echo "restore-dump: every file matches $MANIFEST"
}

# Sets source to the dump's file, checked against the manifest when there is one.
prepare() {
	name="$1.dump"
	source="$DUMP_DIR/$name"
	refuse_parts
	[ -f "$source" ] || fail "$source not found"
	if ! has_manifest; then
		echo "restore-dump: warning, no $MANIFEST (old dump layout); $name is not verified" >&2
		return 0
	fi
	check_manifest
	want=$(manifest_sha "$name")
	if [ -z "$want" ]; then
		echo "restore-dump: $name is not in $MANIFEST, restoring it unverified"
		return 0
	fi
	[ "$(sha "$source")" = "$want" ] ||
		fail "$name does not match the SHA-256 in $MANIFEST, refusing to restore"
	echo "restore-dump: $name matches $MANIFEST"
}

# Creates a database when it does not exist yet.
ensure_db() {
	if ! psql -w -U postgres -d postgres -XtA -c "SELECT 1 FROM pg_database WHERE datname='$1'" | grep -q 1; then
		createdb -w -U postgres "$1" || fail "cannot create database $1"
	fi
}

restore() {
	[ $# -ge 2 ] || fail "usage: restore <dump> <database> [pg_restore options]"
	dump=$1 db=$2
	shift 2
	case "$dump$db" in
	*[!A-Za-z0-9_]*) fail "dump and database names may only use [A-Za-z0-9_]" ;;
	esac
	prepare "$dump"
	export PGPASSWORD="${POSTGRES_PASSWORD:-}"
	ensure_db "$db"
	echo "restore-dump: restoring $dump into $db"
	pg_restore -w -U postgres -d "$db" "$@" "$source" || fail "pg_restore of $dump into $db failed"
	echo "restore-dump: restored $dump into $db"
}

# Prints how many tables a database holds outside the system schemas, failing if it cannot tell.
table_count() {
	count=$(psql -w -U postgres -d "$1" -XtA -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname NOT LIKE 'pg_toast%'")
	case "$count" in
	'' | *[!0-9]*) fail "cannot read the $1 database" ;;
	esac
	echo "$count"
}

# Restores a dump in one transaction with every object owned by a role. Objects the Postgres init
# script already made (extensions, the pgbouncer auth function) are left out of the restore.
restore_owned() {
	dump=$1 db=$2 role=$3
	prepare "$dump"
	ensure_db "$db"
	list=$(mktemp) || fail "cannot create a temporary file"
	pg_restore -l "$source" | grep -v -e ' EXTENSION ' -e ' pgbouncer_get_auth' >"$list" || {
		rm -f "$list"
		fail "cannot list $dump"
	}
	echo "restore-dump: restoring $dump into $db as $role"
	pg_restore -w -U postgres --no-owner --no-acl --role="$role" --single-transaction -L "$list" -d "$db" "$source" || {
		rm -f "$list"
		fail "pg_restore of $dump into $db failed, $db was left as it was"
	}
	rm -f "$list"
	echo "restore-dump: restored $dump into $db"
}

# The knowledge restore setup job: restores knowledge and config only when knowledge has no tables.
restore_if_empty() {
	export PGPASSWORD="${POSTGRES_PASSWORD:-}"
	tables=$(table_count knowledge) || exit 1
	if [ "$tables" -gt 0 ]; then
		echo "restore-dump: knowledge already holds $tables tables, nothing to restore"
		return 0
	fi
	has_manifest || fail "no $MANIFEST in $DUMP_DIR, refusing to restore"
	verify
	tables=$(table_count config) || exit 1
	if [ "$tables" = 0 ]; then
		restore_owned config config "${PG_CONFIG_ROLE:-cc_api}"
	else
		echo "restore-dump: config already has tables, keeping it"
	fi
	restore_owned knowledge knowledge "${PG_KNOWLEDGE_ROLE:-cc_knowledge}"
}

command=${1:-}
[ $# -gt 0 ] && shift
case "$command" in
verify) verify ;;
restore) restore "$@" ;;
restore-if-empty) restore_if_empty ;;
*) fail "usage: restore-dump.sh verify | restore <dump> <database> [pg_restore options] | restore-if-empty" ;;
esac
