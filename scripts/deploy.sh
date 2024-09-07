#!/usr/bin/env bash
set -euxo pipefail

SERVER="opc@shimarin.kuudere.moe"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SOURCE_DIR="$(realpath "$SCRIPT_DIR/../")"

# exclude _build and .git
rsync -avz --exclude '.*' --exclude '_build' --exclude 'deps' "$SOURCE_DIR/" $SERVER:~/thistle_tea/

ssh $SERVER "/home/opc/thistle_tea/scripts/run.sh"
