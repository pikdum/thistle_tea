#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER="opc@shimarin.kuudere.moe"

# exclude _build and .git
rsync -avz --exclude '_build' --exclude '.git' --exclude 'deps' $SCRIPT_DIR/ $SERVER:~/thistle_tea/

ssh $SERVER "cd ~/thistle_tea && ./run.sh"
