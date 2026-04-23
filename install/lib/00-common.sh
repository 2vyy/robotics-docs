# install/lib/00-common.sh — logging, traps, and shared helpers (sourced by main.sh).

robotics_on_exit() {
	local exit_code=$?
	if [[ $exit_code -ne 0 ]]; then
		log_error "Script failed with exit code $exit_code."
		log_error "You can safely re-run this script — it is idempotent."
		log_error "See the wiki: /onboarding/troubleshooting"
	fi
}

robotics_restore_saved_exit_trap() {
	trap - RETURN INT TERM EXIT 2>/dev/null || true
	if [[ -n "${1:-}" ]]; then
		eval "$1"
	else
		trap 'robotics_on_exit' EXIT
	fi
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ "${NO_COLOR:-}" == "1" ]]; then
	RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

log_info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_step() { echo -e "\n${BOLD}${GREEN}▶ $*${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✔]${NC}    $*"; }

# Rich phase header when stdout was a TTY before tee (see main.sh ROBOTICS_CLI_TTY).
# Usage: robotics_phase_begin "0" "Title" "detail line 1" "detail line 2" ...
# Use phase_id "pre" for pre-install checks (log line is "Pre-flight: …", not "Phase pre").
robotics_phase_begin() {
	local phase_id="${1:?phase id (or pre)}"
	local title="${2:?title}"
	shift 2 || true
	if [[ "$phase_id" == "pre" ]]; then
		log_step "Pre-flight: ${title}"
	elif [[ -n "$phase_id" ]]; then
		log_step "Phase ${phase_id}: ${title}"
	else
		log_step "${title}"
	fi
	if [[ "${ROBOTICS_CLI_TTY:-0}" != "1" ]]; then
		return 0
	fi
	local bar="════════════════════════════════════════════════════════════════════════"
	echo -e "${CYAN}${bar}${NC}"
	if [[ "$phase_id" == "pre" ]]; then
		echo -e "${BOLD}${CYAN}Pre-flight${NC} — ${BOLD}${title}${NC}"
	elif [[ -n "$phase_id" ]]; then
		echo -e "${BOLD}${CYAN}Phase ${phase_id}${NC} — ${BOLD}${title}${NC}"
	else
		echo -e "${BOLD}${CYAN}${title}${NC}"
	fi
	echo -e "${CYAN}${bar}${NC}"
	local d
	for d in "$@"; do
		echo -e "  ${CYAN}·${NC} ${d}"
	done
	[[ $# -gt 0 ]] && echo ""
}

robotics_phase_check_banner() {
	if [[ "${ROBOTICS_CLI_TTY:-0}" == "1" ]]; then
		echo -e "${BOLD}  Smoke check${NC}"
	fi
}

run_cmd() {
	if $DRY_RUN; then
		echo -e "${YELLOW}[DRY-RUN]${NC} $*"
	else
		"$@"
	fi
}

bashrc_append() {
	local line="$1"
	if $MODIFY_BASHRC && ! $DRY_RUN; then
		if ! grep -qxF "$line" ~/.bashrc 2>/dev/null; then
			echo "$line" >>~/.bashrc
			log_info "Added to ~/.bashrc: $line"
		fi
	fi
}

is_apt_installed() {
	dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

resolve_existing_path() {
	local p="$1"
	while [[ ! -e "$p" && "$p" != "/" ]]; do
		p="$(dirname "$p")"
	done
	echo "$p"
}

available_gb_for_path() {
	local target resolved
	target="$1"
	resolved="$(resolve_existing_path "$target")"
	df -BG "$resolved" 2>/dev/null | awk 'NR==2 {print $4+0}'
}

check_target_space() {
	local target="$1"
	local required_gb="$2"
	local label="$3"
	local free_gb
	free_gb="$(available_gb_for_path "$target")"
	if [[ -z "$free_gb" || "$free_gb" -lt "$required_gb" ]]; then
		log_error "Only ${free_gb:-0}GB free for ${label} (${target}); need at least ${required_gb}GB."
		exit 1
	fi
	log_info "Disk space for ${label}: ${free_gb}GB free ✓"
}
