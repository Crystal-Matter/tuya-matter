#!/bin/sh
set -eu

if [ "$#" -ne 0 ]; then
    printf 'Usage: %s\n' "$0" >&2
    exit 2
fi

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

exec docker buildx build \
    --pull \
    --platform linux/amd64,linux/arm64 \
    --tag stakach/tuya-matter:latest \
    --push \
    .
