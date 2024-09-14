#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SOURCE_DIR="$(realpath "$SCRIPT_DIR/../")"

cd "$SOURCE_DIR"
sudo podman build . -t thistle_tea
sudo podman auto-update
sudo podman system prune -af
