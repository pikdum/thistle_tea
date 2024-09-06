#!/usr/bin/env bash
set -eu

IMAGE="ghcr.io/pikdum/wow-tools:latest"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OUTPUT_DIR="$(realpath "$SCRIPT_DIR/../")"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

echo "Extracting DBCs from: $WOW_DIR"

# remove existing files
rm -f "$OUTPUT_DIR"/vanilla_dbcs.sqlite*

# extract mpq to dbc
docker run \
    -v "$WOW_DIR":/input/ \
    -v "$TEMP_DIR":/output/ \
    -it "$IMAGE" /usr/local/bin/map-extractor -- -i /input/ -o /output/ -e 2

# transform dbc to sqlite
docker run \
    --user "$(id -u):$(id -g)" \
    -v "$TEMP_DIR/dbc"/:/input/ \
    -v "$OUTPUT_DIR":/output/ \
    -it "$IMAGE" /usr/local/bin/wow_dbc_converter vanilla -i /input/ -o /output/vanilla_dbcs.sqlite

# cleanup
docker run \
    -v "$TEMP_DIR"/:/input/ \
    -it "$IMAGE" sh -c "rm -rf /input/*"

echo ""
echo "Generated $OUTPUT_DIR/vanilla_dbcs.sqlite"
