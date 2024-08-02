#!/usr/bin/env bash
set -euxo pipefail

export PATH="/home/opc/.local/share/mise/shims:$PATH"
export MIX_ENV=prod
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
_build/prod/rel/thistle_tea/bin/thistle_tea stop || true
rm -rf _build
mix deps.get
mix release
_build/prod/rel/thistle_tea/bin/thistle_tea daemon
