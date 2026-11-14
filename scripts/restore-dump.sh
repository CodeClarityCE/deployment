# shellcheck shell=sh
# Verifies dumps against the knowledge dump manifest and restores them, reassembling split dumps.
# Runs on a host or inside the db container (busybox sh). Manifest format: docs/knowledge-dump.md
# in codeclarity-dev.
#
# Usage:
#   sh restore-dump.sh verify
#   sh restore-dump.sh restore <dump> <database> [pg_restore options]
# In the db container: sh -c "$(cat restore-dump.sh)" restore-dump <command> [args]
# Env: DUMP_DIR (default /dump). restore uses POSTGRES_PASSWORD as the postgres password.
#
# Without knowledge-manifest.json (the dump layout before manifests), whole dumps restore
# unverified with a warning, and split parts are refused.

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

has_parts() {
	for part in "$DUMP_DIR/$1".part-*; do
		[ -e "$part" ] && return 0
	done
	return 1
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

# Prints the parts of a split dump, in the order the checksum list gives them.
listed_parts() {
	cut -d' ' -f3 "$DUMP_DIR/$SUMS" | grep "^$1\.part-" || true
}

# Prints the manifest's whole-file SHA-256 of a dump, or nothing if it does not list it.
manifest_sha() {
	manifest_files | while read -r name whole; do
		[ "$name" = "$1" ] && echo "$whole"
	done
}

verify() {
	if ! has_manifest; then
		for f in "$DUMP_DIR"/*.dump.part-*; do
			[ -e "$f" ] && fail "${f##*/} is a split dump part but there is no $MANIFEST, refusing to restore"
		done
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

	for f in "$DUMP_DIR"/*.dump.part-*; do
		[ -e "$f" ] || continue
		grep -q "  ${f##*/}\$" "$DUMP_DIR/$SUMS" || {
			echo "restore-dump: ${f##*/}: not listed in $SUMS" >&2
			bad=1
		}
	done

	files=$(manifest_files)
	while read -r name whole; do
		parts=$(listed_parts "$name")
		if [ -n "$parts" ]; then
			# shellcheck disable=SC2086 # splits the part list into file names
			got=$(cd "$DUMP_DIR" && cat $parts 2>/dev/null | sha)
		else
			got=$(grep "  $name\$" "$DUMP_DIR/$SUMS" | cut -d' ' -f1)
		fi
		if [ "$got" != "$whole" ]; then
			echo "restore-dump: $name: FAILED, does not match the SHA-256 in $MANIFEST" >&2
			bad=1
		fi
	done <<EOF
$files
EOF

	[ "$bad" -eq 0 ] || fail "the dump set in $DUMP_DIR does not match its manifest, nothing was restored"
	echo "restore-dump: every file matches $MANIFEST"
}

# Sets source to a verified file holding the whole dump, reassembling split dumps into staging.
prepare() {
	name="$1.dump"
	source="$DUMP_DIR/$name"
	if ! has_manifest; then
		has_parts "$name" && fail "$name is split but there is no $MANIFEST, refusing to restore"
		[ -f "$source" ] || fail "$source not found"
		echo "restore-dump: warning, no $MANIFEST (old dump layout); $name is not verified" >&2
		return 0
	fi
	check_manifest
	whole=$(manifest_sha "$name")
	if [ -z "$whole" ]; then
		[ -f "$source" ] || fail "$source not found"
		echo "restore-dump: $name is not in $MANIFEST, restoring it unverified"
		return 0
	fi
	parts=$(listed_parts "$name")
	for f in "$DUMP_DIR/$name".part-*; do
		[ -e "$f" ] || continue
		grep -q "  ${f##*/}\$" "$DUMP_DIR/$SUMS" || fail "${f##*/} is not listed in $SUMS, refusing to restore"
	done
	if [ -n "$parts" ]; then
		staging="$DUMP_DIR/.restore.$$"
		mkdir "$staging" || fail "cannot create $staging"
		trap 'rm -rf "$staging"' EXIT
		source="$staging/$name"
		# shellcheck disable=SC2086 # splits the part list into file names
		echo "restore-dump: reassembling $name from $(echo $parts | wc -w | tr -d ' ') parts"
		# shellcheck disable=SC2086 # splits the part list into file names
		(cd "$DUMP_DIR" && cat $parts) >"$source" || fail "cannot reassemble $name"
	elif [ ! -f "$source" ]; then
		fail "$source not found"
	fi
	[ "$(sha "$source")" = "$whole" ] ||
		fail "$name does not match the SHA-256 in $MANIFEST, refusing to restore"
	echo "restore-dump: $name matches $MANIFEST"
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
	if ! psql -w -U postgres -d postgres -XtA -c "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1; then
		createdb -w -U postgres "$db" || fail "cannot create database $db"
	fi
	echo "restore-dump: restoring $dump into $db"
	pg_restore -w -U postgres -d "$db" "$@" "$source" || fail "pg_restore of $dump into $db failed"
	echo "restore-dump: restored $dump into $db"
}

command=${1:-}
[ $# -gt 0 ] && shift
case "$command" in
verify) verify ;;
restore) restore "$@" ;;
*) fail "usage: restore-dump.sh verify | restore <dump> <database> [pg_restore options]" ;;
esac
