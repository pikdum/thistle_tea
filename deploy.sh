#!/usr/bin/env sh
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="opc@shimarin.kuudere.moe"

# exclude _build and .git
rsync -avz --exclude '_build' --exclude '.git' --exclude 'deps' $SCRIPT_DIR/ $SERVER:~/thistle_tea/
