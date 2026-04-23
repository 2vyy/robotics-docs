# install/lib/05-tui.sh — interactive component picker (sourced by main.sh).
# Expects globals: ROS_DISTRO, WS_DIR, UXRCE_AGENT_VERSION, PX4_DIR, VENV_DIR,
# SET_PIP_ALIAS, COMPILE_REQS, INSTALL_*, MODIFY_BASHRC.

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
tui_reset()          { printf '%s' "${_csi}0m"; }
tui_fg()             { printf '%s' "${_csi}${1}m"; }        # e.g. 32 = green
tui_reverse()        { printf '%s' "${_csi}7m"; }
tui_dim()            { printf '%s' "${_csi}2m"; }

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
        local pad=$(( inner_w - ${#t} ))
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
    local -a COMP_OPT_COUNT=( 2  0  2  3  0 )   # ROS GAZEBO PX4 PIP BASHRC
    local -a COMP_OPT_START=( 0 -1  2  4 -1 )   # index into OPT_* arrays (-1 = none)

    # Flat option arrays (ordered: ROS opts first, then PX4, then PIP)
    local -a OPT_LABELS=( "ROS distro" "Workspace " "Agent ver " "PX4 dir   " "venv dir  " "Pip alias " "Hash reqs " )
    local -a OPT_VALS=(   "$ROS_DISTRO"  "$WS_DIR"  "$UXRCE_AGENT_VERSION"  "$PX4_DIR"  "$VENV_DIR" "OFF"       "OFF"       )
    # Which component index owns each option — must stay consistent with COMP_OPT_START/COMP_OPT_COUNT
    local -a OPT_COMP=(   0             0            2                        2           3           3           3           )
    # OPT_TYPE: 0=text, 1=toggle
    local -a OPT_TYPE=(   0             0            0                        0           0           1           1           )

    # Sync toggle values from script defaults
    [[ $SET_PIP_ALIAS == true ]] && OPT_VALS[5]="ON" || OPT_VALS[5]="OFF"
    [[ $COMPILE_REQS == true  ]] && OPT_VALS[6]="ON" || OPT_VALS[6]="OFF"

    # Per-component storage estimates (placeholder — update with accurate values)
    # KB values used for disk space check; display labels shown in confirmation overlay
    local -a COMP_SIZE_KB=(    4200000   1800000    2100000   300000   0     )
    local -a COMP_SIZE_LABEL=( "~4.2 GB" "~1.8 GB" "~2.1 GB" "~0.3 GB" "--" )
    local -a COMP_TIME_MIN=(   15        5          10        2         0    )

    local n_comp=${#COMP_KEYS[@]}

    local _tui_saved_exit_trap
    _tui_saved_exit_trap=$(trap -p EXIT 2>/dev/null || true)

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
        local BOX_H=$(( n_rows + 4 ))   # n_rows content rows + blank separator + hint + 2 borders
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
                if (( is_sel )); then tui_reverse; printf ' '; else printf ' '; fi
                local label; label=$(fit "${COMP_LABELS[$ci]}" 24)
                if (( is_on )); then tui_bold; else tui_dim; fi
                if (( is_sel )); then tui_reverse; fi
                printf '%s' "$label"
                tui_reset

                # expand indicator — right-aligned, only when ON and has opts
                if (( is_on && has_opts > 0 )); then
                    tui_move "$screen_row" $(( BOX_COL + BOX_W - 2 ))
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
                local type="${OPT_TYPE[$oi]}"

                if (( is_sel )); then
                    tui_fg 220; tui_bold
                    printf '  > %s ' "${OPT_LABELS[$oi]}"
                    tui_reset
                    
                    if [[ $type == 1 ]]; then
                        # Toggle type
                        if [[ $val == "ON" ]]; then
                            tui_fg 32; tui_bold; tui_reverse; printf ' ON '; tui_reset
                        else
                            tui_fg 90; tui_reverse; printf ' OFF '; tui_reset
                        fi
                    else
                        # Text type
                        tui_fg 33; tui_bold
                        if $editing; then
                            printf '['; fit "$val" $(( val_w - 3 )); printf ']>'
                        else
                            printf '['; fit "$val" $(( val_w - 2 )); printf ']'
                        fi
                        tui_reset
                    fi
                else
                    tui_fg 240
                    printf '  > %s ' "${OPT_LABELS[$oi]}"
                    tui_reset
                    
                    if [[ $type == 1 ]]; then
                         if [[ $val == "ON" ]]; then
                            tui_fg 32; printf 'ON'; tui_reset
                        else
                            tui_fg 90; printf 'OFF'; tui_reset
                        fi
                    else
                        tui_fg 37
                        fit "$val" "$val_w"
                        tui_reset
                    fi
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
            local oi="${cur_entry#opt:}"
            if [[ ${OPT_TYPE[$oi]} == 1 ]]; then
                printf 'SPACE toggle  ↑↓ move  < back'
            else
                printf 'ENTER edit  ↑↓ move  < back'
            fi
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

    render_confirm() {
        # ── Disk space check ──────────────────────────────────────────────────
        local avail_kb
        avail_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)

        local total_kb=0
        local total_min=0
        local i
        for (( i = 0; i < n_comp; i++ )); do
            if (( COMP_ON[i] )); then
                (( total_kb  += COMP_SIZE_KB[i]  ))
                (( total_min += COMP_TIME_MIN[i] ))
            fi
        done

        local space_ok=true
        (( avail_kb < total_kb )) && space_ok=false

        # ── Format available space for display ────────────────────────────────
        local avail_gb
        avail_gb=$(awk "BEGIN{printf \"%.1f\", $avail_kb/1048576}")

        # ── Draw overlay ──────────────────────────────────────────────────────
        local ow=58   # overlay width — must fit "!! Insufficient disk space" line
        local oh=$(( n_comp + 10 ))
        local start_row=$(( (TERM_ROWS - oh) / 2 ))
        local start_col=$(( (TERM_COLS - ow) / 2 ))

        draw_box "$start_row" "$start_col" "$oh" "$ow" "Confirm Installation"

        local r=$(( start_row + 1 ))
        local c=$(( start_col + 2 ))

        tui_move "$r" "$c"; tui_fg 90; printf 'The following will be installed:'; tui_reset
        (( r++ ))
        tui_move "$r" "$c"   # blank line
        (( r++ ))

        for (( i = 0; i < n_comp; i++ )); do
            if (( COMP_ON[i] )); then
                tui_move "$r" "$c"
                tui_fg 32; printf '[+] '; tui_reset
                printf '%-26s' "${COMP_LABELS[$i]}"
                tui_fg 90; printf '%s' "${COMP_SIZE_LABEL[$i]}"; tui_reset
                (( r++ ))
            fi
        done

        (( r++ ))   # blank line

        # total storage
        local total_gb
        total_gb=$(awk "BEGIN{printf \"%.1f\", $total_kb/1048576}")
        tui_move "$r" "$c"
        tui_fg 90; printf 'Total storage:  '; tui_reset
        tui_bold; printf '~%s GB' "$total_gb"; tui_reset
        (( r++ ))

        # available space — red if insufficient
        tui_move "$r" "$c"
        tui_fg 90; printf 'Available:      '; tui_reset
        if $space_ok; then
            tui_fg 32; printf '%s GB    OK' "$avail_gb"; tui_reset
        else
            tui_fg 31; tui_bold; printf '%s GB    !! Insufficient disk space' "$avail_gb"; tui_reset
        fi
        (( r++ ))

        # estimated time
        tui_move "$r" "$c"
        tui_fg 90; printf 'Est. time:      '; tui_reset
        tui_bold; printf '~%d min' "$total_min"; tui_reset
        (( r++ ))
        (( r++ ))   # blank line

        # buttons
        tui_move "$r" "$c"
        if $space_ok; then
            tui_fg 32; tui_bold; tui_reverse; printf ' Y / ENTER  Confirm '; tui_reset
            printf '   '
            tui_fg 90; printf 'ESC / N  Go back'; tui_reset
        else
            tui_fg 90; printf '(free up space to continue)'; tui_reset
            printf '   '
            tui_fg 90; printf 'ESC / N  Go back'; tui_reset
        fi
    }

    # ── Inline text editor for a sub-option field ─────────────────────────────
    edit_field() {
        local oi=$1
        local val="${OPT_VALS[$oi]}"
        local orig_val="$val"   # snapshot for discard on ESC
        editing=true

        while true; do
            render_header
            render_panel
            read_key
            case "$KEY" in
                ENTER|TAB)
                    OPT_VALS[$oi]="$val"
                    editing=false
                    break ;;
                ESC|QUIT)
                    OPT_VALS[$oi]="$orig_val"   # restore original
                    editing=false
                    break ;;
                *)
                    if [[ "$KEY" == $'\x7f' || "$KEY" == $'\b' ]]; then
                        val="${val%?}"
                    elif [[ ${#KEY} -eq 1 ]]; then
                        val+="$KEY"
                    fi
                    OPT_VALS[$oi]="$val"
                    ;;
            esac
        done
        editing=false
    }

    # ── Main event loop ────────────────────────────────────────────────────────
    while ! $done; do
        render_header
        render_panel

        if $confirm_open; then
            render_confirm
            read_key
            case "$KEY" in
                ENTER|y|Y)
                    local avail_kb
                    avail_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
                    local total_kb=0
                    local _i
                    for (( _i = 0; _i < n_comp; _i++ )); do
                        (( COMP_ON[_i] )) && (( total_kb += COMP_SIZE_KB[_i] ))
                    done
                    if (( avail_kb >= total_kb )); then
                        done=true
                    fi
                    ;;
                ESC|QUIT|n|N)
                    confirm_open=false
                    ;;
            esac
            continue
        fi

        read_key
        build_flat_list
        local n_rows=${#FLAT_LIST[@]}
        local cur_entry="${FLAT_LIST[$cursor]}"

        case "$KEY" in
            QUIT|ESC)
                _tui_cleanup
                exit 0
                ;;

            UP)
                (( cursor > 0 )) && (( cursor-- ))
                ;;

            DOWN)
                (( cursor < n_rows - 1 )) && (( cursor++ ))
                ;;

            RIGHT)
                if [[ "$cur_entry" == comp:* ]]; then
                    local ci="${cur_entry#comp:}"
                    if (( COMP_ON[ci] && COMP_OPT_COUNT[ci] > 0 && !expanded[ci] )); then
                        expanded[$ci]=1
                    fi
                fi
                ;;

            LEFT)
                if [[ "$cur_entry" == opt:* ]]; then
                    local oi="${cur_entry#opt:}"
                    local parent_comp="${OPT_COMP[$oi]}"
                    local fi
                    for (( fi = 0; fi < n_rows; fi++ )); do
                        if [[ "${FLAT_LIST[$fi]}" == "comp:$parent_comp" ]]; then
                            cursor=$fi
                            break
                        fi
                    done
                elif [[ "$cur_entry" == comp:* ]]; then
                    local ci="${cur_entry#comp:}"
                    expanded[$ci]=0
                fi
                ;;

            SPACE)
                if [[ "$cur_entry" == comp:* ]]; then
                    local ci="${cur_entry#comp:}"
                    COMP_ON[$ci]=$(( 1 - COMP_ON[ci] ))
                    (( !COMP_ON[ci] )) && expanded[$ci]=0
                    build_flat_list
                    n_rows=${#FLAT_LIST[@]}
                    (( cursor >= n_rows )) && cursor=$(( n_rows - 1 ))
                elif [[ "$cur_entry" == opt:* ]]; then
                    local oi="${cur_entry#opt:}"
                    if [[ ${OPT_TYPE[$oi]} == 1 ]]; then
                        if [[ ${OPT_VALS[$oi]} == "ON" ]]; then
                            OPT_VALS[$oi]="OFF"
                        else
                            OPT_VALS[$oi]="ON"
                        fi
                    fi
                fi
                ;;

            ENTER)
                if [[ "$cur_entry" == opt:* ]]; then
                    local oi="${cur_entry#opt:}"
                    if [[ ${OPT_TYPE[$oi]} == 0 ]]; then
                        edit_field "$oi"
                    fi
                elif [[ "$cur_entry" == "install" ]]; then
                    confirm_open=true
                fi
                ;;

            e|E)
                local _all_exp=true
                local _ci
                for (( _ci = 0; _ci < n_comp; _ci++ )); do
                    if (( COMP_ON[_ci] && COMP_OPT_COUNT[_ci] > 0 && !expanded[_ci] )); then
                        _all_exp=false
                        break
                    fi
                done
                if $_all_exp; then
                    for (( _ci = 0; _ci < n_comp; _ci++ )); do expanded[$_ci]=0; done
                else
                    for (( _ci = 0; _ci < n_comp; _ci++ )); do
                        (( COMP_ON[_ci] && COMP_OPT_COUNT[_ci] > 0 )) && expanded[$_ci]=1
                    done
                fi
                ;;
        esac
    done

    _tui_cleanup
    robotics_restore_saved_exit_trap "${_tui_saved_exit_trap}"

    # ── Apply selections back to script variables ─────────────────────────────
    local idx
    for (( idx = 0; idx < n_comp; idx++ )); do
        case "${COMP_KEYS[$idx]}" in
            ROS)    INSTALL_ROS=$(    [[ ${COMP_ON[$idx]} == 1 ]] && echo true || echo false) ;;
            GAZEBO) INSTALL_GAZEBO=$( [[ ${COMP_ON[$idx]} == 1 ]] && echo true || echo false) ;;
            PX4)    INSTALL_PX4=$(    [[ ${COMP_ON[$idx]} == 1 ]] && echo true || echo false) ;;
            PIP)    INSTALL_PIP=$(    [[ ${COMP_ON[$idx]} == 1 ]] && echo true || echo false) ;;
            BASHRC) MODIFY_BASHRC=$(  [[ ${COMP_ON[$idx]} == 1 ]] && echo true || echo false) ;;
        esac
    done

    # OPT_VALS order: ROS distro(0), Workspace(1), Agent ver(2), PX4 dir(3), venv dir(4), Pip alias(5), Hash reqs(6)
    ROS_DISTRO="${OPT_VALS[0]}"
    WS_DIR="${OPT_VALS[1]}"
    UXRCE_AGENT_VERSION="${OPT_VALS[2]}"
    PX4_DIR="${OPT_VALS[3]}"
    VENV_DIR="${OPT_VALS[4]}"
    SET_PIP_ALIAS=$([[ ${OPT_VALS[5]} == "ON" ]] && echo true || echo false)
    COMPILE_REQS=$([[ ${OPT_VALS[6]} == "ON" ]] && echo true || echo false)
}
