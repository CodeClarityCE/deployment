#!/bin/bash
# Database dumps are stored in Git (knowledge.dump uses LFS)
# They are automatically available after clone/pull

cd "$(dirname "$0")/.."

# Check if knowledge.dump exists and is not a pointer file
if [ ! -s dump/knowledge.dump ] || [ $(wc -c < dump/knowledge.dump) -lt 1000 ]; then
    echo "Pulling knowledge.dump from Git LFS..."
    git lfs pull --include="dump/knowledge.dump"
fi

echo "Database dumps available in deployment/dump/"
