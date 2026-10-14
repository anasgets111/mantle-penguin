#!/bin/bash
# Starts Pip, or stops it when it is already running. Uses the mantle binaries in ./bin.
dir=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
mantle=$dir/bin/mantle
if "$mantle" list 2>/dev/null | awk -v d="$dir" '$NF == d { found = 1 } END { exit !found }'; then
    exec "$mantle" -c "$dir" stop
fi
exec "$mantle" -c "$dir" -d
