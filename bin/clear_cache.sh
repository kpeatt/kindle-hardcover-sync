#!/bin/sh

DIR="$( cd "$( dirname "$0" )/.." && pwd )"
CACHE_FILE="$DIR/hc_cache.txt"

if [ -f "$CACHE_FILE" ]; then
    rm "$CACHE_FILE"
    eips -m "Hardcover cache cleared!"
else
    eips -m "Cache is already empty."
fi