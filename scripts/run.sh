#!/usr/bin/env bash
set -euxo pipefail

export PATH="/home/opc/.local/share/mise/shims:$PATH"
export MIX_ENV=prod
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SOURCE_DIR="$(realpath "$SCRIPT_DIR/../")"

cd "$SOURCE_DIR"
_build/prod/rel/thistle_tea/bin/thistle_tea stop || true
rm -rf _build
mix deps.get
mix release
_build/prod/rel/thistle_tea/bin/thistle_tea daemon
