#!/bin/sh
set -eu
SCRIPT_ROOT="$(CDPATH= cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_ROOT/verify_healthkit_signing.py" "$@"
