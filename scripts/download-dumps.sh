#!/bin/bash
# Database dumps are stored in Git; knowledge and config dumps and their parts use LFS.
# Pulls any file still an LFS pointer, then verifies the set against knowledge-manifest.json.

cd "$(dirname "$0")/.." || exit 1

# An LFS file not yet downloaded is a small text pointer.
pointers=0
for f in dump/*.dump dump/*.dump.part-*; do
    [ -f "$f" ] || continue
    if [ "$(wc -c <"$f")" -lt 1000 ] && head -c 100 "$f" | grep -q '^version https://git-lfs'; then
        pointers=1
    fi
done
if [ ! -f dump/knowledge.dump ] && ! ls dump/knowledge.dump.part-* >/dev/null 2>&1; then
    pointers=1
fi

if [ "$pointers" -eq 1 ]; then
    echo "Pulling database dumps from Git LFS..."
    git lfs pull --include="dump/*.dump,dump/*.dump.part-*" || {
        echo "Error: git lfs pull failed" >&2
        exit 1
    }
fi

DUMP_DIR=dump sh scripts/restore-dump.sh verify || {
    echo "Error: the database dumps in deployment/dump do not match their manifest" >&2
    exit 1
}

echo "Database dumps available in deployment/dump/"
