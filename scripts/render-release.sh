#!/bin/sh
# Renders the files a deployment release attaches: the Compose file with every image pinned
# by digest, every config file inlined and the release version set, and .env.example set to
# that version. Also writes release-notes.md, naming the knowledge dump image and every image.
# Fails, writing nothing, when an image's digest cannot be found.
# Only image references and config files change: ${...} meant for the operator's .env stays.
#
# Usage: sh scripts/render-release.sh <version> <source dir> <out dir>
# Needs docker (buildx imagetools) logged in where the images live, and jq.
set -eu

[ $# -eq 3 ] || { echo "usage: render-release.sh <version> <source dir> <out dir>" >&2; exit 2; }
version=$1 src=$2 out=$3
case "$version" in
"" | *[!0-9A-Za-z.+_-]*) echo "render-release: unexpected version: $version" >&2; exit 2 ;;
esac
compose="$src/docker-compose.yaml"
[ -f "$compose" ] || { echo "render-release: no $compose" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
	echo "render-release: $*" >&2
	exit 1
}

# Every image value: image: keys and x-*-image anchors; aliases point at one of those.
image_values() {
	sed -n -E 's/^[[:space:]]*(image|x-[a-z-]*image):[[:space:]]*(&[^[:space:]]+[[:space:]]+)?//p' "$1" |
		sed 's/[[:space:]]*$//' | grep -v '^\*' | sort -u
}

# Prints ref@digest, keeping the tag, using the registry's manifest (list) digest.
pin() {
	digest=$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>"$tmp/inspect.err" | jq -er .digest 2>/dev/null) ||
		fail "cannot find the digest of $1: $(cat "$tmp/inspect.err")"
	echo "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || fail "unexpected digest for $1: $digest"
	echo "$1@$digest"
}

# Map of "<value>\t<pinned value>"; a ${VAR:-default} value keeps VAR and pins its default.
image_values "$compose" >"$tmp/values"
: >"$tmp/map"
while IFS= read -r value; do
	ref=$value prefix="" suffix=""
	# shellcheck disable=SC2016 # matches a literal ${VAR:-default}
	if expr "$value" : '\${[A-Za-z_][A-Za-z0-9_]*:-.*}$' >/dev/null; then
		prefix=${value%%:-*}:-
		ref=${value#*:-}
		ref=${ref%\}}
		suffix="}"
	fi
	case "$ref" in
	*'$'* | "") fail "cannot pin an image that is only set by a variable: $value" ;;
	*@*)
		echo "$ref" | grep -Eq '@sha256:[0-9a-f]{64}$' || fail "unexpected digest in $value"
		pinned=$ref
		;;
	*) pinned=$(pin "$ref") ;;
	esac
	printf '%s\t%s%s%s\n' "$value" "$prefix" "$pinned" "$suffix" >>"$tmp/map"
done <"$tmp/values"

awk -v map="$tmp/map" '
BEGIN {
	while ((getline line < map) > 0) {
		tab = index(line, "\t")
		pinned[substr(line, 1, tab - 1)] = substr(line, tab + 1)
	}
}
match($0, /^[ \t]*(image|x-[a-z-]*image):[ \t]*(&[^ \t]+[ \t]+)?/) {
	value = substr($0, RLENGTH + 1)
	sub(/[ \t]+$/, "", value)
	if (value in pinned) {
		print substr($0, 1, RLENGTH) pinned[value]
		next
	}
}
{ print }
' "$compose" >"$tmp/docker-compose.yaml"

# Inlines each top-level config file as content; Compose interpolates content, so $ becomes $$.
awk -v src="$src" '
/^[^ ]/ { top = $0 }
top == "configs:" && /^    file:[ \t]/ {
	path = $0
	sub(/^    file:[ \t]+/, "", path)
	sub(/[ \t]+$/, "", path)
	if (path !~ /^\//) path = src "/" path
	n = 0
	while ((status = (getline line < path)) > 0) {
		gsub(/\$/, "$$", line)
		lines[++n] = line
	}
	if (status < 0) {
		print "render-release: cannot read config file " path > "/dev/stderr"
		exit 1
	}
	close(path)
	# Compose treats empty content as no content, so an empty file cannot be inlined.
	if (n == 0) {
		print "render-release: config file " path " is empty" > "/dev/stderr"
		exit 1
	}
	print "    content: |2"
	for (i = 1; i <= n; i++) print (lines[i] == "" ? "" : "      " lines[i])
	next
}
{ print }
' "$tmp/docker-compose.yaml" >"$tmp/inlined.yaml"

# Stamps the release version the version-check job compares with .env.
marker='x-release-version: &release-version ""'
[ "$(grep -cxF "$marker" "$tmp/inlined.yaml")" = 1 ] || fail "$compose needs exactly one line: $marker"
sed "s/^$marker\$/x-release-version: \&release-version \"$version\"/" "$tmp/inlined.yaml" >"$tmp/out.yaml"

[ "$(grep -c '^CODECLARITY_VERSION=' "$src/.env.example")" = 1 ] || fail "$src/.env.example needs one CODECLARITY_VERSION= line"
sed "s/^CODECLARITY_VERSION=.*/CODECLARITY_VERSION=$version/" "$src/.env.example" >"$tmp/env"

dump=$(cut -f2 "$tmp/map" | sed -n 's/^\${[A-Za-z_][A-Za-z0-9_]*:-\(.*\)}$/\1/; /^codeclarityce\/knowledge-dump[:@]/p')
[ "$(echo "$dump" | grep -c .)" = 1 ] || fail "expected one codeclarityce/knowledge-dump image, found: ${dump:-none}"
{
	echo "Knowledge dump: \`$dump\`, restored on first start (KNOWLEDGE_DUMP_IMAGE in .env overrides it)."
	echo
	echo "Images, pinned by digest in \`docker-compose.yaml\`:"
	echo
	cut -f2 "$tmp/map" | sed 's/^\${[A-Za-z_][A-Za-z0-9_]*:-\(.*\)}$/\1/; s/.*/- `&`/'
} >"$tmp/notes"

mkdir -p "$out"
cp "$tmp/out.yaml" "$out/docker-compose.yaml"
cp "$tmp/env" "$out/.env.example"
cp "$tmp/notes" "$out/release-notes.md"
