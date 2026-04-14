#!/usr/bin/env bash
# =============================================================================
#  robotics-setup.sh
#
#  One-stop installer for ROS 2 Jazzy + Gazebo Harmonic + PX4 SITL + uXRCE-DDS
#  + common Python/pip packages on Ubuntu 24.04 (Noble Numbat).
#
#  Designed to be:
#   • Idempotent   – safe to re-run at any time
#   • Modular      – use flags to install only what you need
#   • Transparent  – every step is printed before execution
#   • Compatible   – native Ubuntu 24.04, WSL2, and Distrobox
#
#  Usage:
#     ./robotics-setup.sh [OPTIONS]
#
#  Options:
#     --full           Install everything (default if no flags given)
#     --ros-only       Install ROS 2 Jazzy Desktop + dev tools only
#     --gazebo-only    Install Gazebo Harmonic + ros_gz integration only
#     --px4-only       Install PX4-Autopilot SITL + uXRCE-DDS agent only
#     --pip-only       Install Python venv + pip packages only
#     --no-ros         Skip ROS 2
#     --no-gazebo      Skip Gazebo
#     --no-px4         Skip PX4
#     --no-pip         Skip pip / Python packages
#     --no-bashrc      Do not modify ~/.bashrc
#     --rebuild        Force rebuilding PX4 and ROS workspace
#     --dry-run        Print actions without making changes
#     --no-color       Disable colored output
#     --ros-distro D   Use different ROS distro (default: jazzy)
#     --agent-ver V    Use different uXRCE Agent version (default: v2.4.3)
#     --px4-dir DIR    Clone PX4-Autopilot into DIR (default: ~/PX4-Autopilot)
#     --venv-dir DIR   Create Python venv at DIR (default: ~/ros2_venv)
#     --ws-dir DIR     ROS 2 workspace dir (default: ~/ros2_ws)
#     --help           Show this help message
#
#  Requirements:
#     Ubuntu 24.04 LTS (Noble Numbat), amd64 or aarch64
#     Internet connection
#     ~30 GB free disk space (full install)
#
#  License: MIT
# =============================================================================

set -Euo pipefail

# ─── Settings & Logging ──────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

LOGFILE="$HOME/ros2-jazzy-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Color helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [[ "${NO_COLOR:-}" == "1" ]]; then
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_step()    { echo -e "\n${BOLD}${GREEN}▶ $*${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[✔]${NC}    $*"; }

log_info "Full log being written to $LOGFILE"

# ─── Trap handler ────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed at line $BASH_LINENO with exit code $exit_code."
        log_error "You can safely re-run this script – it is idempotent."
    fi
}
trap cleanup EXIT

# ─── Defaults ────────────────────────────────────────────────────────────────
INSTALL_ROS=true
INSTALL_GAZEBO=true
INSTALL_PX4=true
INSTALL_PIP=true
MODIFY_BASHRC=true
REBUILD=false
DRY_RUN=false

PX4_DIR="$HOME/PX4-Autopilot"
VENV_DIR="$HOME/ros2_venv"
WS_DIR="$HOME/ros2_ws"

UXRCE_AGENT_VERSION="v2.4.3"
ROS_DISTRO="jazzy"
UBUNTU_CODENAME="noble"

# ─── Pure-Bash TUI (no whiptail / dialog / tput dependency) ──────────────────
#
#  Controls:
#   ↑ / ↓       move cursor
#   SPACE        toggle checkbox  (checklist panel)
#   ENTER        edit field value  (advanced panel) / confirm on summary screen
#   LEFT/RIGHT   switch between panels
#   q / ESC      quit / cancel
# ─────────────────────────────────────────────────────────────────────────────

# ── Terminal primitives via raw ANSI (no tput required) ──────────────────────
_esc=$'\033'
_csi="${_esc}["

tui_cursor_hide()    { printf '%s' "${_csi}?25l"; }
tui_cursor_show()    { printf '%s' "${_csi}?25h"; }
tui_alt_screen()     { printf '%s' "${_esc}[?1049h"; }
tui_normal_screen()  { printf '%s' "${_esc}[?1049l"; }
tui_clear()          { printf '%s' "${_csi}2J${_csi}H"; }
tui_move()           { printf '%s' "${_csi}${1};${2}H"; }   # row col (1-based)
tui_bold()           { printf '%s' "${_csi}1m"; }
tui_dim()            { printf '%s' "${_csi}2m"; }
tui_reset()          { printf '%s' "${_csi}0m"; }
tui_fg()             { printf '%s' "${_csi}${1}m"; }        # e.g. 32 = green
tui_bg()             { printf '%s' "${_csi}${1}m"; }        # e.g. 44 = blue bg
tui_reverse()        { printf '%s' "${_csi}7m"; }

# ── Read a single keypress; sets KEY and handles arrow escape sequences ───────
read_key() {
    local _ch _seq
    # Use stty -echo -icanon min 1 time 0 as configured in launch_tui
    IFS= read -rsn1 _ch
    if [[ $_ch == $'\033' ]]; then
        IFS= read -rsn2 -t 0.05 _seq 2>/dev/null || true
        case "$_seq" in
            '[A') KEY="UP"   ;;
            '[B') KEY="DOWN" ;;
            '[C') KEY="RIGHT";;
            '[D') KEY="LEFT" ;;
            *)    KEY="ESC"  ;;
        esac
    elif [[ $_ch == $'\t' ]]; then  KEY="TAB"
    elif [[ $_ch == $'\n' || $_ch == $'\r' || $_ch == '' ]]; then KEY="ENTER"
    elif [[ $_ch == ' '  ]]; then   KEY="SPACE"
    elif [[ $_ch == 'q' || $_ch == 'Q' ]]; then KEY="QUIT"
    else                            KEY="$_ch"
    fi
}

# ── Box-drawing helpers ───────────────────────────────────────────────────────
# Draw a single-line box.  Args: top-row  left-col  height  width  title
draw_box() {
    local row=$1 col=$2 h=$3 w=$4 title="${5:-}"
    local bottom=$(( row + h - 1 ))
    local right=$(( col + w - 1 ))
    local inner_w=$(( w - 2 ))

    # top border
    tui_move "$row" "$col"
    printf '+'
    if [[ -n $title ]]; then
        local t=" ${title} "
        local tlen=${#t}
        local pad=$(( inner_w - tlen ))
        local lpad=$(( pad / 2 ))
        local rpad=$(( pad - lpad ))
        printf '%*s' "$lpad" '' | tr ' ' '-'
        tui_bold; printf '%s' "$t"; tui_reset
        printf '%*s' "$rpad" '' | tr ' ' '-'
    else
        printf '%*s' "$inner_w" '' | tr ' ' '-'
    fi
    printf '+'

    # sides
    local r
    for (( r = row + 1; r < bottom; r++ )); do
        tui_move "$r" "$col";   printf '|'
        tui_move "$r" "$right"; printf '|'
    done

    # bottom border
    tui_move "$bottom" "$col"
    printf '+'
    printf '%*s' "$inner_w" '' | tr ' ' '-'
    printf '+'
}

# ── Truncate or left-pad a string to exactly N printable chars ────────────────
fit() {
    local s="$1" w=$2
    if (( ${#s} >= w )); then printf '%s' "${s:0:$w}"
    else printf '%-*s' "$w" "$s"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main TUI entry point
# ═══════════════════════════════════════════════════════════════════════════════
launch_tui() {
    # ── Component definitions ─────────────────────────────────────────────────
    local -a COMP_KEYS=(   ROS                    GAZEBO             PX4                      PIP                      BASHRC           )
    local -a COMP_LABELS=( "ROS 2 Jazzy Desktop"  "Gazebo Harmonic"  "PX4 SITL + uXRCE-DDS"  "Python venv + packages" "Modify ~/.bashrc" )
    local -a COMP_ON=(     1                       1                  1                        1                        1                )

    # Per-component option counts and start indices into OPT_* arrays
    # COMP_OPT_COUNT=0 means no sub-options (no indicator shown)
    local -a COMP_OPT_COUNT=( 2  0  2  1  0 )   # ROS GAZEBO PX4 PIP BASHRC
    local -a COMP_OPT_START=( 0 -1  2  4 -1 )   # index into OPT_* arrays (-1 = none)

    # Flat option arrays (ordered: ROS opts first, then PX4, then PIP)
    local -a OPT_LABELS=( "ROS distro" "Workspace " "Agent ver " "PX4 dir   " "venv dir  " )
    local -a OPT_VALS=(   "$ROS_DISTRO"  "$WS_DIR"  "$UXRCE_AGENT_VERSION"  "$PX4_DIR"  "$VENV_DIR" )
    # Which component index owns each option — must stay consistent with COMP_OPT_START/COMP_OPT_COUNT
    local -a OPT_COMP=(   0             0            2                        2           3           )

    # Per-component storage estimates (placeholder — update with accurate values)
    # KB values used for disk space check; display labels shown in confirmation overlay
    local -a COMP_SIZE_KB=(    4200000   1800000    2100000   300000   0     )
    local -a COMP_SIZE_LABEL=( "~4.2 GB" "~1.8 GB" "~2.1 GB" "~0.3 GB" "--" )
    local -a COMP_TIME_MIN=(   15        5          10        2         0    )

    local n_comp=${#COMP_KEYS[@]}
    local n_opt=${#OPT_LABELS[@]}

    # ── Layout constants ───────────────────────────────────────────────────────
    local TERM_ROWS TERM_COLS
    TERM_ROWS=$(stty size 2>/dev/null | cut -d' ' -f1 || echo 24)
    TERM_COLS=$(stty size 2>/dev/null | cut -d' ' -f2 || echo 80)

    local BOX_COL=2
    local BOX_W=$(( TERM_COLS - 3 ))
    local BOX_ROW=4      # row 1=title, row 2=divider, row 3=blank, panel starts row 4

    # ── State ─────────────────────────────────────────────────────────────────
    local -a expanded=()
    local _ei; for (( _ei = 0; _ei < n_comp; _ei++ )); do expanded+=(0); done
    local cursor=0                   # index into FLAT_LIST
    local editing=false
    local confirm_open=false
    local done=false

    # FLAT_LIST: built by build_flat_list(); entries are "comp:N", "opt:N", "install"
    local -a FLAT_LIST=()

    # ── Terminal setup ─────────────────────────────────────────────────────────
    local OLD_STTY
    OLD_STTY=$(stty -g 2>/dev/null || true)
    tui_alt_screen
    tui_cursor_hide
    stty -echo -icanon min 1 time 0 2>/dev/null || true

    # Restore terminal unconditionally
    _tui_cleanup() {
        stty "$OLD_STTY" 2>/dev/null || true
        tui_cursor_show
        tui_normal_screen
    }
    trap '_tui_cleanup' RETURN INT TERM EXIT

    # ── Flat list builder — call before every render ───────────────────────────
    # Populates FLAT_LIST with entries: "comp:N", "opt:N", or "install"
    build_flat_list() {
        FLAT_LIST=()
        local i j
        for (( i = 0; i < n_comp; i++ )); do
            FLAT_LIST+=("comp:$i")
            local count=${COMP_OPT_COUNT[$i]}
            local start=${COMP_OPT_START[$i]}
            # Only show sub-options when component is ON and expanded
            if (( COMP_ON[i] && expanded[i] && count > 0 )); then
                for (( j = start; j < start + count; j++ )); do
                    FLAT_LIST+=("opt:$j")
                done
            fi
        done
        FLAT_LIST+=("install")
    }

    # ── Render helpers ─────────────────────────────────────────────────────────
    render_header() {
        tui_clear
        tui_move 1 1
        tui_fg 36; tui_bold
        local title="  🤖  Robotics Stack Installer  -  ROS 2 Jazzy + Gazebo Harmonic + PX4 SITL"
        fit "$title" $(( TERM_COLS - 2 ))
        tui_reset
        tui_move 2 1
        tui_fg 90
        printf '%*s' $(( TERM_COLS - 2 )) '' | tr ' ' '-'
        tui_reset
    }

    render_panel() {
        build_flat_list
        local n_rows=${#FLAT_LIST[@]}
        local BOX_H=$(( n_rows + 3 ))   # +1 header row, +1 blank separator, +1 hint row
        local inner_w=$(( BOX_W - 2 ))
        local val_w=$(( inner_w - 16 ))  # space for "  > Label  [value]"

        draw_box "$BOX_ROW" "$BOX_COL" "$BOX_H" "$BOX_W" "Components"

        local flat_idx
        local screen_row=$(( BOX_ROW + 1 ))

        for (( flat_idx = 0; flat_idx < n_rows; flat_idx++ )); do
            local entry="${FLAT_LIST[$flat_idx]}"
            local is_sel=$(( flat_idx == cursor ))
            tui_move "$screen_row" $(( BOX_COL + 2 ))

            # ── Install button row ────────────────────────────────────────────
            if [[ "$entry" == "install" ]]; then
                if (( is_sel )); then
                    tui_fg 32; tui_bold; tui_reverse
                    printf '[ Install ]'
                    tui_reset
                else
                    tui_fg 32; tui_bold
                    printf '[ Install ]'
                    tui_reset
                fi
                (( screen_row++ ))
                continue
            fi

            # ── Component row ─────────────────────────────────────────────────
            if [[ "$entry" == comp:* ]]; then
                local ci="${entry#comp:}"
                local is_on=${COMP_ON[$ci]}
                local has_opts=${COMP_OPT_COUNT[$ci]}
                local is_exp=${expanded[$ci]}

                if (( is_sel )); then tui_reverse; fi

                # checkbox
                if (( is_on )); then
                    tui_fg 32; printf '[+]'; tui_reset
                else
                    tui_fg 90; printf '[ ]'; tui_reset
                fi
                if (( is_sel )); then tui_reverse; fi

                printf ' '
                local label; label=$(fit "${COMP_LABELS[$ci]}" 24)
                if (( is_on )); then tui_bold; else tui_dim; fi
                if (( is_sel )); then tui_reverse; fi
                printf '%s' "$label"
                tui_reset

                # expand indicator — right-aligned, only when ON and has opts
                if (( is_on && has_opts > 0 )); then
                    tui_move "$screen_row" $(( BOX_COL + BOX_W - 3 ))
                    if (( is_exp )); then
                        tui_fg 220; printf 'v'; tui_reset
                    else
                        tui_fg 240; printf '>'; tui_reset
                    fi
                fi

                (( screen_row++ ))
                continue
            fi

            # ── Sub-option row ────────────────────────────────────────────────
            if [[ "$entry" == opt:* ]]; then
                local oi="${entry#opt:}"
                local val="${OPT_VALS[$oi]}"

                if (( is_sel )); then
                    tui_fg 220; tui_bold
                    printf '  > %s ' "${OPT_LABELS[$oi]}"
                    tui_reset
                    tui_fg 33; tui_bold
                    if $editing; then
                        printf '['; fit "$val" $(( val_w - 3 )); printf ']>'
                    else
                        printf '['; fit "$val" $(( val_w - 2 )); printf ']'
                    fi
                    tui_reset
                else
                    tui_fg 240
                    printf '  > %s ' "${OPT_LABELS[$oi]}"
                    tui_reset
                    tui_fg 37
                    fit "$val" "$val_w"
                    tui_reset
                fi

                (( screen_row++ ))
                continue
            fi
        done

        # blank separator row
        tui_move "$screen_row" $(( BOX_COL + 2 ))
        (( screen_row++ ))

        # hint row — context-sensitive
        tui_move "$screen_row" $(( BOX_COL + 2 ))
        tui_fg 90
        local cur_entry="${FLAT_LIST[$cursor]}"
        if [[ "$cur_entry" == opt:* ]]; then
            printf 'ENTER edit  ↑↓ move  < back'
        else
            # Compute whether all expandable ON components are currently expanded
            local _all_exp=true
            local _ci
            for (( _ci = 0; _ci < n_comp; _ci++ )); do
                if (( COMP_ON[_ci] && COMP_OPT_COUNT[_ci] > 0 && !expanded[_ci] )); then
                    _all_exp=false
                    break
                fi
            done
            if $_all_exp; then
                printf 'SPACE toggle  ↑↓ move  > expand  E collapse all  ENTER install'
            else
                printf 'SPACE toggle  ↑↓ move  > expand  E expand all   ENTER install'
            fi
        fi
        tui_reset
    }

    render_status() {
        tui_move "$STATUS_ROW" 1
        tui_reset

        local on_list=""
        local i
        for (( i = 0; i < n_comp; i++ )); do
            if (( COMP_ON[i] )); then on_list+="${COMP_LABELS[$i]}, "; fi
        done
        on_list="${on_list%, }"

        tui_fg 90
        printf '  Will install: '
        tui_fg 32; tui_bold
        printf '%s' "${on_list:-none}"
        tui_reset

        tui_move $(( STATUS_ROW + 1 )) 1
        tui_fg 90
        printf '  [ENTER] Confirm & Install    [q / ESC] Cancel'
        tui_reset
    }

    # ── Inline text editor for an advanced field ───────────────────────────────
    edit_field() {
        local idx=$1
        local val="${ADV_VALS[$idx]}"
        editing=true
        render_right_panel

        while true; do
            read_key
            case "$KEY" in
                ENTER|TAB)
                    ADV_VALS[$idx]="$val"
                    editing=false
                    break ;;
                ESC|QUIT)
                    editing=false   # discard
                    break ;;
                *)
                    # Backspace
                    if [[ "$KEY" == $'\x7f' || "$KEY" == $'\b' ]]; then
                        val="${val%?}"
                    elif [[ ${#KEY} -eq 1 ]]; then
                        val+="$KEY"
                    fi
                    ADV_VALS[$idx]="$val"
                    render_right_panel
                    ;;
            esac
        done
        editing=false
    }

    # ── Main event loop ────────────────────────────────────────────────────────
    while ! $done; do
        render_header
        render_left_panel
        render_right_panel
        render_status

        read_key
        case "$KEY" in
            QUIT|ESC)
                _tui_cleanup
                exit 0
                ;;
            LEFT|RIGHT)
                panel=$(( 1 - panel ))   # flip between 0 and 1
                ;;
            UP)
                if (( panel == 0 )); then
                    (( l_cursor > 0 )) && (( l_cursor-- ))
                else
                    (( r_cursor > 0 )) && (( r_cursor-- ))
                fi
                ;;
            DOWN)
                if (( panel == 0 )); then
                    (( l_cursor < n_comp - 1 )) && (( l_cursor++ ))
                else
                    (( r_cursor < n_adv - 1 )) && (( r_cursor++ ))
                fi
                ;;
            SPACE)
                if (( panel == 0 )); then
                    COMP_ON[$l_cursor]=$(( 1 - COMP_ON[l_cursor] ))
                fi
                ;;
            ENTER)
                if (( panel == 1 )); then
                    edit_field "$r_cursor"
                else
                    done=true   # confirm from left panel too
                fi
                ;;
        esac
    done

    _tui_cleanup

    # ── Apply selections back to script variables ─────────────────────────────
    local idx
    for (( idx = 0; idx < n_comp; idx++ )); do
        case "${COMP_KEYS[$idx]}" in
            ROS)    INSTALL_ROS=$(( COMP_ON[idx] == 1 && echo true || echo false)) ;;
            GAZEBO) INSTALL_GAZEBO=$(( COMP_ON[idx] == 1 && echo true || echo false)) ;;
            PX4)    INSTALL_PX4=$(( COMP_ON[idx] == 1 && echo true || echo false)) ;;
            PIP)    INSTALL_PIP=$(( COMP_ON[idx] == 1 && echo true || echo false)) ;;
            BASHRC) MODIFY_BASHRC=$(( COMP_ON[idx] == 1 && echo true || echo false)) ;;
        esac
    done

    ROS_DISTRO="${ADV_VALS[0]}"
    UXRCE_AGENT_VERSION="${ADV_VALS[1]}"
    PX4_DIR="${ADV_VALS[2]}"
    VENV_DIR="${ADV_VALS[3]}"
    WS_DIR="${ADV_VALS[4]}"
}

# ─── Argument parsing ────────────────────────────────────────────────────────
if [[ $# -eq 0 ]] && [[ -t 0 ]]; then
    launch_tui
else
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                INSTALL_ROS=true; INSTALL_GAZEBO=true; INSTALL_PX4=true; INSTALL_PIP=true ;;
            --ros-only)
                INSTALL_ROS=true; INSTALL_GAZEBO=false; INSTALL_PX4=false; INSTALL_PIP=false ;;
            --gazebo-only)
                INSTALL_ROS=false; INSTALL_GAZEBO=true; INSTALL_PX4=false; INSTALL_PIP=false ;;
            --px4-only)
                INSTALL_ROS=false; INSTALL_GAZEBO=false; INSTALL_PX4=true; INSTALL_PIP=false ;;
            --pip-only)
                INSTALL_ROS=false; INSTALL_GAZEBO=false; INSTALL_PX4=false; INSTALL_PIP=true ;;
            --no-ros)     INSTALL_ROS=false ;;
            --no-gazebo)  INSTALL_GAZEBO=false ;;
            --no-px4)     INSTALL_PX4=false ;;
            --no-pip)     INSTALL_PIP=false ;;
            --no-bashrc)  MODIFY_BASHRC=false ;;
            --rebuild)    REBUILD=true ;;
            --dry-run)    DRY_RUN=true ;;
            --no-color)   RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC='' ;;
            --ros-distro) ROS_DISTRO="$2"; shift ;;
            --agent-ver)  UXRCE_AGENT_VERSION="$2"; shift ;;
            --px4-dir)    PX4_DIR="$2"; shift ;;
            --venv-dir)   VENV_DIR="$2"; shift ;;
            --ws-dir)     WS_DIR="$2"; shift ;;
            --help|-h)
                sed -n '/^# ====/,/^# ====/p' "$0" | sed 's/^# //' | sed 's/^#//'
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

# If Gazebo, PX4, or Pip are requested, we need the ROS base (repos + keys)
INSTALL_ROS_BASE=false
if $INSTALL_ROS || $INSTALL_GAZEBO || $INSTALL_PX4 || $INSTALL_PIP; then
    INSTALL_ROS_BASE=true
fi

# ─── Pre-flight checks ──────────────────────────────────────────────────────
log_step "Pre-flight checks"

if $DRY_RUN; then
    log_warn "DRY RUN MODE — no changes will be made to your system."
fi

# Check if running as root/sudo
if [[ $EUID -eq 0 ]]; then
    log_error "This script should NOT be run with sudo or as root."
    exit 1
fi

# Free disk space check
FREE_GB=$(df -BG /home | awk 'NR==2 {print $4+0}')
if [[ $FREE_GB -lt 30 ]]; then
    log_error "Only ${FREE_GB}GB free in /home. Need ≥30 GB for full install."
    exit 1
fi
log_info "Disk space: ${FREE_GB}GB free ✓"

# RAM hint
RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
log_info "Total RAM: ${RAM_TOTAL} (use 'free -h' for details) ✓"

# Must be Ubuntu 24.04 (skip if not on Ubuntu for local tests, but normally required)
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${VERSION_ID:-}" != "24.04" ]]; then
        log_error "This script requires Ubuntu 24.04 (Noble Numbat)."
        exit 1
    fi
fi

# ─── Command Wrapper ─────────────────────────────────────────────────────────
run_cmd() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# ─── Helper: append a line to ~/.bashrc if not already present ───────────────
bashrc_append() {
    local line="$1"
    if $MODIFY_BASHRC && ! $DRY_RUN; then
        if ! grep -qxF "$line" ~/.bashrc 2>/dev/null; then
            echo "$line" >> ~/.bashrc
            log_info "Added to ~/.bashrc: $line"
        fi
    fi
}

# ─── Helper: check if an apt package is installed ───────────────────────────
is_apt_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 0 — System update & locale
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Step 0: System update & locale configuration"

if ! $DRY_RUN; then
    log_info "Setting up UTF-8 locale..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq locales >/dev/null
    sudo locale-gen en_US.UTF-8 >/dev/null
    sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    export LANG=en_US.UTF-8

    log_info "Consolidated apt update & upgrade..."
    sudo apt-get update -qq
    sudo apt-get upgrade -y -qq
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1 — ROS 2 Base / Repository Setup
# ═══════════════════════════════════════════════════════════════════════════════
install_ros_base() {
    log_step "Step 1: ROS 2 Base Security & Repository Setup"

    run_cmd sudo apt-get install -y -qq build-essential cmake curl git gnupg lsb-release wget software-properties-common

    if [[ ! -f /etc/apt/sources.list.d/ros2.list ]]; then
        log_info "Adding ROS 2 apt repository..."
        run_cmd sudo add-apt-repository -y universe
        run_cmd sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-ring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-ring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" | \
            run_cmd sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
        run_cmd sudo apt-get update -qq
    fi

    log_info "Installing ROS 2 development tools..."
    run_cmd sudo apt-get install -y -qq \
        python3-colcon-common-extensions python3-rosdep python3-vcstool \
        python3-argcomplete ros-dev-tools

    if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        run_cmd sudo rosdep init || true
    fi
    run_cmd rosdep update --rosdistro="${ROS_DISTRO}" || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2 — ROS 2 Jazzy Desktop
# ═══════════════════════════════════════════════════════════════════════════════
install_ros_desktop() {
    log_step "Step 2: ROS 2 Jazzy Desktop Installation"
    if is_apt_installed "ros-${ROS_DISTRO}-desktop"; then
        log_info "ros-${ROS_DISTRO}-desktop already installed ✓"
    else
        run_cmd sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
    fi
    bashrc_append "source /opt/ros/${ROS_DISTRO}/setup.bash"
    source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Gazebo Harmonic
# ═══════════════════════════════════════════════════════════════════════════════
install_gazebo() {
    log_step "Step 3: Gazebo Harmonic + ROS Integration"
    source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null || true
    
    if is_apt_installed "ros-${ROS_DISTRO}-ros-gz"; then
        log_info "ros-${ROS_DISTRO}-ros-gz already installed ✓"
    else
        run_cmd sudo apt-get install -y "ros-${ROS_DISTRO}-ros-gz"
    fi

    log_info "Installing additional Gazebo vendor packages (suppressing noise)..."
    run_cmd sudo apt-get install -y -qq \
        "ros-${ROS_DISTRO}-gz-sim-vendor" "ros-${ROS_DISTRO}-gz-math-vendor" \
        "ros-${ROS_DISTRO}-gz-transport-vendor" "ros-${ROS_DISTRO}-gz-tools-vendor" \
        "ros-${ROS_DISTRO}-sdformat-urdf" "ros-${ROS_DISTRO}-gz-ros2-control" \
        2>/dev/null || log_warn "Optional Gazebo packages had issues – usually safe to ignore."

    bashrc_append "export GZ_VERSION=harmonic"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4 — PX4 SITL + Agent + Workspace
# ═══════════════════════════════════════════════════════════════════════════════
install_px4() {
    log_step "Step 4: PX4 SITL & DDS Bridge"
    
    if [[ -d "${PX4_DIR}/.git" ]]; then
        log_info "PX4 already present at ${PX4_DIR}"
        run_cmd git -C "${PX4_DIR}" pull --rebase || true
    else
        run_cmd git clone --recursive https://github.com/PX4/PX4-Autopilot.git "${PX4_DIR}"
    fi

    log_info "Ensuring PX4 dependencies (ubuntu.sh)..."
    run_cmd bash "${PX4_DIR}/Tools/setup/ubuntu.sh" --no-nuttx

    # Smarter build logic
    if $REBUILD || [[ ! -f "${PX4_DIR}/build/px4_sitl_default/bin/px4" ]]; then
        log_info "Building PX4 SITL (this may take 10+ min)..."
        (cd "${PX4_DIR}" && run_cmd make px4_sitl)
    else
        log_info "PX4 SITL already built — skipping (use --rebuild to force)"
    fi

    # Agent
    if [[ ! -f /usr/local/bin/MicroXRCEAgent ]]; then
        log_info "Building Micro XRCE-DDS Agent ${UXRCE_AGENT_VERSION}..."
        (
            TEMP_AGENT="/tmp/XRCE-Agent"
            run_cmd git clone -b "${UXRCE_AGENT_VERSION}" https://github.com/eProsima/Micro-XRCE-DDS-Agent.git "${TEMP_AGENT}"
            cd "${TEMP_AGENT}" && mkdir build && cd build
            run_cmd cmake .. && run_cmd make -j"$(nproc)"
            run_cmd sudo make install
            run_cmd sudo ldconfig /usr/local/lib/
        )
    fi

    # Workspace
    mkdir -p "${WS_DIR}/src"
    if [[ ! -d "${WS_DIR}/src/px4_msgs" ]]; then
        run_cmd git -C "${WS_DIR}/src" clone https://github.com/PX4/px4_msgs.git
    fi
    
    if $REBUILD || [[ ! -f "${WS_DIR}/install/setup.bash" ]]; then
        log_info "Building ROS 2 workspace..."
        (cd "${WS_DIR}" && source "/opt/ros/${ROS_DISTRO}/setup.bash" && run_cmd colcon build --symlink-install)
    fi
    bashrc_append "source ${WS_DIR}/install/setup.bash"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Python/Pip (using uv)
# ═══════════════════════════════════════════════════════════════════════════════
install_uv() {
    if command -v uv &>/dev/null; then
        log_info "uv already installed: $(uv --version) ✓"
    else
        log_info "Installing uv (package manager)..."
        run_cmd curl -LsSf https://astral.sh/uv/install.sh | sh
        # Ensure uv is on PATH for current session
        export PATH="$HOME/.local/bin:$PATH"
        bashrc_append 'export PATH="$HOME/.local/bin:$PATH"'
    fi
}

install_pip() {
    log_step "Step 5: Python Virtual Environment (uv)"
    install_uv

    if [[ ! -d "${VENV_DIR}" ]]; then
        log_info "Creating virtual environment at ${VENV_DIR}..."
        # --seed adds pip inside the venv for any tooling that calls pip directly
        # --system-site-packages ensures ROS system packages are visible
        run_cmd uv venv --seed --system-site-packages --python python3 "${VENV_DIR}"
    fi
    
    if [[ -f "${SCRIPT_DIR}/requirements-ros2.txt" ]]; then
        log_info "Installing pip packages from requirements-ros2.txt using uv..."
        # uv pip install is a high-performance drop-in for pip install -r
        run_cmd uv pip install --python "${VENV_DIR}/bin/python" \
            -r "${SCRIPT_DIR}/requirements-ros2.txt"
    else
        log_warn "requirements-ros2.txt not found! Skipping pip packages."
    fi
    
    bashrc_append "source ${VENV_DIR}/bin/activate"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Post-install & Summary
# ═══════════════════════════════════════════════════════════════════════════════
post_install() {
    log_step "Final Summary"

    if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
        log_info "Detected WSL2 — install latest Windows GPU drivers + restart WSL for best performance."
    fi

    log_success "Installation complete! See the wiki for next steps:"
    log_info "  - Verify your install: http://localhost:4321/onboarding/verify"
    log_info "  - First flight test:   http://localhost:4321/onboarding/px4-test"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────
log_info "Starting robotics-setup.sh overhaul..."
START_TIME=$(date +%s)

$INSTALL_ROS_BASE && install_ros_base
$INSTALL_ROS      && install_ros_desktop
$INSTALL_GAZEBO   && install_gazebo
$INSTALL_PX4      && install_px4
$INSTALL_PIP      && install_pip

post_install

END_TIME=$(date +%s)
log_info "Total time: $(( (END_TIME - START_TIME) / 60 ))m $(( (END_TIME - START_TIME) % 60 ))s"