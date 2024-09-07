#!/usr/bin/env bash
set -eu

IMAGE="ghcr.io/pikdum/wow-tools:latest"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
OUTPUT_DIR="$(realpath "$SCRIPT_DIR/../db/")"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf $TEMP_DIR' EXIT

echo "Extracting DBCs from: $WOW_DIR"

# extract mpq to dbc
docker run \
    --rm \
    -v "$WOW_DIR":/input/ \
    -v "$TEMP_DIR":/output/ \
    -t "$IMAGE" /usr/local/bin/map-extractor -- -i /input/ -o /output/ -e 2

# remove existing files
rm -f "$OUTPUT_DIR"/dbc.sqlite*

# transform dbc to sqlite
docker run \
    --rm \
    --user "$(id -u):$(id -g)" \
    -v "$TEMP_DIR/dbc"/:/input/ \
    -v "$OUTPUT_DIR":/output/ \
    -t "$IMAGE" /usr/local/bin/wow_dbc_converter vanilla -i /input/ -o /output/dbc.sqlite

# cleanup
docker run \
    --rm \
    -v "$TEMP_DIR"/:/input/ \
    -t "$IMAGE" sh -c "rm -rf /input/*"

echo ""
echo "Generated $OUTPUT_DIR/dbc.sqlite"
