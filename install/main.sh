#!/usr/bin/env bash
# Robotics stack installer — modular entrypoint (see install/BEHAVIOR.md).
# Run from a git checkout, or via bootstrap.sh after curl.

set -Euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

_MAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="${INSTALL_SOURCE_DIR:-$_MAIN_DIR}"
LIB="${INSTALL_ROOT}/lib"

# Capture TTY before stdout is redirected through tee (pipe would make -t 1 false).
export ROBOTICS_CLI_TTY=0
[[ -t 1 ]] && ROBOTICS_CLI_TTY=1

for __a in "$@"; do
	if [[ "$__a" == "--no-color" ]]; then
		export NO_COLOR=1
		break
	fi
done

# shellcheck source=lib/00-common.sh
source "${LIB}/00-common.sh"
robotics_require_ubuntu_24_04 || exit 1

LOGFILE="${ROBOTICS_LOG_FILE:-$HOME/ros2-jazzy-install.log}"
export LOGFILE
export ROBOTICS_LOG_FILE="$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# shellcheck source=lib/08-phase-verify.sh
source "${LIB}/08-phase-verify.sh"
trap 'robotics_on_exit' EXIT

log_info "Full log: ${LOGFILE}"
log_info "Install bundle directory: ${INSTALL_ROOT}"
if [[ "${ROBOTICS_CLI_TTY:-0}" == "1" ]]; then
	log_info "Interactive terminal: phase plan lines will show extra detail on stdout."
fi

INSTALL_ROS=true
INSTALL_GAZEBO=true
INSTALL_PX4=true
INSTALL_PIP=true
MODIFY_BASHRC=true
SET_PIP_ALIAS=false
COMPILE_REQS=false
REBUILD=false
DRY_RUN=false
ORIGINAL_ARGC=$#

PX4_DIR="$HOME/PX4-Autopilot"
VENV_DIR="$HOME/ros2_venv"
WS_DIR="$HOME/ros2_ws"

UXRCE_AGENT_VERSION="v2.4.3"
ROS_DISTRO="jazzy"
UBUNTU_CODENAME="noble"

INSTALL_CACHE="${ROBOTICS_CACHE_DIR:-$HOME/.robotics-setup}"
mkdir -p "${INSTALL_CACHE}"
REQUIREMENTS_FILE="${INSTALL_CACHE}/requirements.txt"

print_help() {
	cat <<'EOF'
=============================================================================
 robotics install (install/main.sh)

 ROS 2 Jazzy + Gazebo Harmonic + PX4 SITL + uXRCE-DDS + Python tooling
 on Ubuntu 24.04 (Noble).

 Usage:
    ./install/main.sh [OPTIONS]
    curl -fsSL …/install/bootstrap.sh | bash -s -- [OPTIONS]

 Core options:
    --full           Install everything (default if no flags given)
    --no-ros         Skip ROS 2 desktop
    --no-gazebo      Skip Gazebo
    --no-px4         Skip PX4
    --no-pip         Skip pip / Python packages
    --no-bashrc      Do not modify ~/.bashrc
    --rebuild        Force rebuilding PX4 and ROS workspace
    --dry-run        Print actions without making changes
    --no-color       Disable colored output
    --ros-distro D   Use different ROS distro (default: jazzy)
    --agent-ver V    Use different uXRCE Agent version (default: v2.4.3)
    --px4-dir DIR    Clone PX4-Autopilot into DIR (default: ~/PX4-Autopilot)
    --venv-dir DIR   Create Python venv at DIR (default: ~/ros2_venv)
    --ws-dir DIR     ROS 2 workspace dir (default: ~/ros2_ws)
    --help           Show this help message

 Advanced options:
    --ros-only       ROS 2 desktop + dev tools only
    --gazebo-only    Gazebo + ros_gz only (still needs ROS base apt)
    --px4-only       PX4 SITL + uXRCE-DDS only (still needs ROS base apt)
    --pip-only       Python venv + packages only (still needs ROS base apt)
    --pip-alias      Add alias pip='uv pip' to ~/.bashrc
    --compile-reqs   Re-generate a hashed requirements.txt using uv

 Environment:
    ROBOTICS_INSTALL_REF   Git ref for bootstrap raw URLs (default: main)
    ROBOTICS_INSTALL_REPO  owner/repo on GitHub (default: 2vyy/robotics-docs)
    ROBOTICS_LOG_FILE      Override log path
    ROBOTICS_CACHE_DIR     Where generated requirements.txt is stored
=============================================================================
EOF
}

# shellcheck source=lib/05-tui.sh
source "${LIB}/05-tui.sh"
# shellcheck source=lib/10-preflight.sh
source "${LIB}/10-preflight.sh"
# shellcheck source=lib/20-system-base.sh
source "${LIB}/20-system-base.sh"
# shellcheck source=lib/30-ros-base.sh
source "${LIB}/30-ros-base.sh"
# shellcheck source=lib/40-ros-desktop.sh
source "${LIB}/40-ros-desktop.sh"
# shellcheck source=lib/50-gazebo.sh
source "${LIB}/50-gazebo.sh"
# shellcheck source=lib/60-px4.sh
source "${LIB}/60-px4.sh"
# shellcheck source=lib/70-python.sh
source "${LIB}/70-python.sh"
# shellcheck source=lib/90-post-install.sh
source "${LIB}/90-post-install.sh"

# TUI needs a real keyboard TTY on stdin (not a pipe). bootstrap.sh re-attaches </dev/tty when you use curl|bash.
if [[ $# -eq 0 ]] && [[ -t 0 ]]; then
	launch_tui
else
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--full)
			INSTALL_ROS=true
			INSTALL_GAZEBO=true
			INSTALL_PX4=true
			INSTALL_PIP=true
			;;
		--ros-only)
			INSTALL_ROS=true
			INSTALL_GAZEBO=false
			INSTALL_PX4=false
			INSTALL_PIP=false
			;;
		--gazebo-only)
			INSTALL_ROS=false
			INSTALL_GAZEBO=true
			INSTALL_PX4=false
			INSTALL_PIP=false
			;;
		--px4-only)
			INSTALL_ROS=false
			INSTALL_GAZEBO=false
			INSTALL_PX4=true
			INSTALL_PIP=false
			;;
		--pip-only)
			INSTALL_ROS=false
			INSTALL_GAZEBO=false
			INSTALL_PX4=false
			INSTALL_PIP=true
			;;
		--no-ros) INSTALL_ROS=false ;;
		--no-gazebo) INSTALL_GAZEBO=false ;;
		--no-px4) INSTALL_PX4=false ;;
		--no-pip) INSTALL_PIP=false ;;
		--no-bashrc) MODIFY_BASHRC=false ;;
		--rebuild) REBUILD=true ;;
		--dry-run) DRY_RUN=true ;;
		--no-color)
			RED=''
			GREEN=''
			YELLOW=''
			CYAN=''
			BOLD=''
			NC=''
			;;
		--ros-distro)
			ROS_DISTRO="$2"
			shift
			;;
		--agent-ver)
			UXRCE_AGENT_VERSION="$2"
			shift
			;;
		--px4-dir)
			PX4_DIR="$2"
			shift
			;;
		--venv-dir)
			VENV_DIR="$2"
			shift
			;;
		--ws-dir)
			WS_DIR="$2"
			shift
			;;
		--pip-alias) SET_PIP_ALIAS=true ;;
		--compile-reqs) COMPILE_REQS=true ;;
		--help | -h)
			print_help
			exit 0
			;;
		*)
			log_error "Unknown option: $1   (use --help for usage)"
			exit 1
			;;
		esac
		shift
	done
fi

if [[ $ORIGINAL_ARGC -eq 0 ]] && [[ ! -t 0 ]]; then
	log_warn "Non-interactive run detected with no flags; defaulting to --full install."
	log_warn "This can download tens of GB. Press Ctrl-C now to cancel."
	for ((i = 10; i >= 1; i--)); do
		printf '\rStarting in %2ss... ' "$i"
		sleep 1
	done
	printf '\n'
fi

INSTALL_ROS_BASE=false
if $INSTALL_ROS || $INSTALL_GAZEBO || $INSTALL_PX4 || $INSTALL_PIP; then
	INSTALL_ROS_BASE=true
fi

robotics_phase_begin "pre" "System checks before install" \
	"Confirm Ubuntu 24.04, free disk for selected components, not root" \
	"RAM hint (full PX4 + sim builds benefit from 16GB+)"
robotics_run_preflight
verify_phase_preflight

log_info "Starting robotics setup..."
ROBOTICS_INSTALL_BEGAN=1
START_TIME=$(date +%s)

robotics_phase_begin "0" "System update and locale" \
	"apt-get update and full upgrade" \
	"Install locales; set en_US.UTF-8 as default"
install_system_base
verify_phase_system_base

if $INSTALL_ROS_BASE; then
	robotics_phase_begin "1" "ROS 2 apt repository and build tools" \
		"ROS 2 apt key and ros2.list" \
		"colcon, rosdep, vcstool, ros-dev-tools" \
		"rosdep init / update (may warn on first run)"
	install_ros_base
	verify_phase_ros_base
fi

if $INSTALL_ROS; then
	robotics_phase_begin "2" "ROS 2 desktop (${ROS_DISTRO})" \
		"Install ros-${ROS_DISTRO}-desktop via apt" \
		"Append source /opt/ros/${ROS_DISTRO}/setup.bash to ~/.bashrc when enabled"
	install_ros_desktop
	verify_phase_ros_desktop
fi

if $INSTALL_GAZEBO; then
	robotics_phase_begin "3" "Gazebo Harmonic and ROS integration" \
		"Install ros-${ROS_DISTRO}-ros-gz and related vendor packages" \
		"Export GZ_VERSION=harmonic in ~/.bashrc when enabled"
	install_gazebo
	verify_phase_gazebo
fi

if $INSTALL_PX4; then
	robotics_phase_begin "4" "PX4 SITL, Micro XRCE-DDS agent, and px4_msgs workspace" \
		"Clone or update PX4-Autopilot under ${PX4_DIR}" \
		"Run upstream Tools/setup/ubuntu.sh --no-nuttx" \
		"make px4_sitl; build MicroXRCEAgent; colcon build px4_msgs in ${WS_DIR}"
	install_px4
	verify_phase_px4
fi

if $INSTALL_PIP; then
	robotics_phase_begin "5" "Python tooling (uv) and venv" \
		"Install uv; optional ruff / ty / just via uv tool" \
		"Create ${VENV_DIR} with --system-site-packages for ROS Python" \
		"pip install from bundled requirements; optional pip-audit"
	install_pip
	verify_phase_pip
fi

post_install

END_TIME=$(date +%s)
log_info "Total time: $(((END_TIME - START_TIME) / 60))m $(((END_TIME - START_TIME) % 60))s"
