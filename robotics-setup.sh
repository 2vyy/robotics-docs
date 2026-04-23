#!/usr/bin/env bash
# Compatibility wrapper — delegates to the modular installer in install/main.sh.

set -euo pipefail
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${_SCRIPT_DIR}/install/main.sh" "$@"
