#!/usr/bin/env bash
# Minimal bootstrap: fetch modular installer from GitHub raw, then run main.sh.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/2vyy/robotics-docs/REF/install/bootstrap.sh | bash
#   curl ... | bash -s -- --dry-run
#
# Pin REF with a tag or commit for reproducibility (default: main).

set -euo pipefail

if [[ ${EUID:-0} -eq 0 ]]; then
	echo "Do not run this installer as root or with sudo." >&2
	exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
	echo "curl is required. Install with: sudo apt-get install -y curl" >&2
	exit 1
fi

REF="${ROBOTICS_INSTALL_REF:-main}"
REPO="${ROBOTICS_INSTALL_REPO:-2vyy/robotics-docs}"
BASE="https://raw.githubusercontent.com/${REPO}/${REF}/install"

ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT

export INSTALL_SOURCE_DIR="${ROOT}"

fetch() {
	local rel="$1"
	mkdir -p "${ROOT}/$(dirname "$rel")"
	curl -fsSL "${BASE}/${rel}" -o "${ROOT}/${rel}"
}

# Order matters: main sources lib in this order.
for rel in \
	lib/00-common.sh \
	lib/08-phase-verify.sh \
	lib/05-tui.sh \
	lib/10-preflight.sh \
	lib/20-system-base.sh \
	lib/30-ros-base.sh \
	lib/40-ros-desktop.sh \
	lib/50-gazebo.sh \
	lib/60-px4.sh \
	lib/70-python.sh \
	lib/90-post-install.sh \
	main.sh; do
	fetch "$rel"
done

chmod +x "${ROOT}/main.sh"
bash "${ROOT}/main.sh" "$@"
