# TUI Inline Options Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two-panel TUI (Components + Advanced Options) with a single accordion-style panel where sub-options expand inline beneath their parent component, with a navigable Install button and confirmation overlay.

**Architecture:** All changes are confined to `launch_tui()` in `robotics-setup.sh`. The function's data arrays, state variables, render helpers, and event loop are each replaced in sequence. A `build_flat_list()` helper computes the ordered list of visible rows on every render, making cursor movement trivially correct.

**Tech Stack:** Pure bash, ANSI escape codes, no external TUI dependencies.

---

## File map

| File | Change |
|------|--------|
| `robotics-setup.sh:104-112` | Update controls comment block |
| `robotics-setup.sh:203-490` | Full rewrite of `launch_tui()` |

---

### Task 1: Restructure data arrays inside `launch_tui`

Replace the two separate array sets (`COMP_*` and `ADV_*`) with a unified structure that encodes which component owns which options.

**Files:**
- Modify: `robotics-setup.sh:204-232`

- [ ] **Step 1: Replace the data array block**

Find and replace from `# ── Component definitions` through the end of `ADV_VALS=(...)` (lines 204–232) with:

```bash
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
    # Which component index does each option belong to?
    local -a OPT_COMP=(   0             0            2                        2           3           )

    # Per-component storage estimates (placeholder — update with accurate values)
    # KB values used for disk space check; display labels shown in confirmation overlay
    local -a COMP_SIZE_KB=(    4200000   1800000    2100000   300000   0     )
    local -a COMP_SIZE_LABEL=( "~4.2 GB" "~1.8 GB" "~2.1 GB" "~0.3 GB" "--" )
    local -a COMP_TIME_MIN=(   15        5          10        2         0    )

    local n_comp=${#COMP_KEYS[@]}
    local n_opt=${#OPT_LABELS[@]}
```

- [ ] **Step 2: Verify script still parses**

```bash
bash -n robotics-setup.sh
```
Expected: no output (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "refactor(tui): restructure data arrays for inline sub-options"
```

---

### Task 2: Replace layout constants and state variables

Single panel, dynamic box height, new state variables.

**Files:**
- Modify: `robotics-setup.sh:234-255`

- [ ] **Step 1: Replace layout constants and state block**

Replace from `# ── Layout constants` through `local done=false` with:

```bash
    # ── Layout constants ───────────────────────────────────────────────────────
    local TERM_ROWS TERM_COLS
    TERM_ROWS=$(stty size 2>/dev/null | cut -d' ' -f1 || echo 24)
    TERM_COLS=$(stty size 2>/dev/null | cut -d' ' -f2 || echo 80)

    local BOX_COL=2
    local BOX_W=$(( TERM_COLS - 3 ))
    local BOX_ROW=4

    # ── State ─────────────────────────────────────────────────────────────────
    local -a expanded=(0 0 0 0 0)   # per-component expanded flag
    local all_expanded=false
    local cursor=0                   # index into FLAT_LIST
    local editing=false
    local confirm_open=false
    local done=false

    # FLAT_LIST: built by build_flat_list(); entries are "comp:N", "opt:N", "install"
    local -a FLAT_LIST=()
```

- [ ] **Step 2: Verify script still parses**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "refactor(tui): replace two-panel layout constants with single-panel state"
```

---

### Task 3: Add `build_flat_list` helper

Computes the ordered list of visible rows based on current `COMP_ON[]` and `expanded[]` state.

**Files:**
- Modify: `robotics-setup.sh` — insert after the `_tui_cleanup` trap line

- [ ] **Step 1: Add `build_flat_list` inside `launch_tui`, after the trap line**

```bash
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
```

- [ ] **Step 2: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "feat(tui): add build_flat_list helper for dynamic row computation"
```

---

### Task 4: Rewrite `render_panel` (replaces `render_left_panel` + `render_right_panel`)

Single-panel render. Draws the box with dynamic height, all visible rows, and context-sensitive hint.

**Files:**
- Modify: `robotics-setup.sh` — replace `render_left_panel()` and `render_right_panel()` with `render_panel()`

- [ ] **Step 1: Delete `render_left_panel` and `render_right_panel`, insert `render_panel`**

```bash
    render_panel() {
        build_flat_list
        local n_rows=${#FLAT_LIST[@]}
        local BOX_H=$(( n_rows + 3 ))   # +1 header, +1 hint, +1 blank separator row
        local inner_w=$(( BOX_W - 2 ))
        local val_w=$(( inner_w - 16 ))  # space left after "    ▸ Label  ["

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

                # expand indicator (right-aligned, only when ON and has opts)
                if (( is_on && has_opts > 0 )); then
                    # move to right side of inner box
                    tui_move "$screen_row" $(( BOX_COL + BOX_W - 3 ))
                    if (( is_exp )); then
                        tui_fg 220; printf 'v'; tui_reset   # expanded
                    else
                        tui_fg 240; printf '>'; tui_reset   # collapsed
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
                        # show edit cursor
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

        # hint row (inside box, above bottom border)
        tui_move "$screen_row" $(( BOX_COL + 2 ))
        tui_fg 90
        local on_opt_row=false
        local cur_entry="${FLAT_LIST[$cursor]}"
        [[ "$cur_entry" == opt:* ]] && on_opt_row=true

        if $on_opt_row; then
            printf 'ENTER edit  ↑↓ move  < back'
        elif $all_expanded; then
            printf 'SPACE toggle  ↑↓ move  > expand  E collapse all  ENTER install'
        else
            printf 'SPACE toggle  ↑↓ move  > expand  E expand all   ENTER install'
        fi
        tui_reset
    }
```

- [ ] **Step 2: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "feat(tui): add render_panel replacing two-panel render functions"
```

---

### Task 5: Rewrite `render_status` → `render_confirm` (confirmation overlay)

Replaces the old status bar with a centred confirmation overlay that includes disk space check.

**Files:**
- Modify: `robotics-setup.sh` — replace `render_status()` with `render_confirm()`

- [ ] **Step 1: Replace `render_status` with `render_confirm`**

```bash
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
        local ow=46   # overlay width
        local oh=$(( n_comp + 9 ))  # rows: header+blank+items+blank+totals+blank+buttons+hint
        local start_row=$(( (TERM_ROWS - oh) / 2 ))
        local start_col=$(( (TERM_COLS - ow) / 2 ))

        # Dim the background by redrawing panel without cursor highlight would
        # be expensive; instead draw the overlay box directly on top.
        draw_box "$start_row" "$start_col" "$oh" "$ow" "Confirm Installation"

        local r=$(( start_row + 1 ))
        local c=$(( start_col + 2 ))

        tui_move "$r" "$c"; tui_fg 90; printf 'The following will be installed:'; tui_reset
        (( r++ ))
        tui_move "$r" "$c"; printf ''   # blank line
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

        # available space (red if insufficient)
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
```

- [ ] **Step 2: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "feat(tui): add render_confirm overlay with disk space check"
```

---

### Task 6: Update `edit_field`

Now takes an `opt_idx` into `OPT_VALS` (not the old `ADV_VALS`) and re-renders the full panel instead of just the right panel.

**Files:**
- Modify: `robotics-setup.sh` — replace the existing `edit_field()` body

- [ ] **Step 1: Replace `edit_field`**

```bash
    # ── Inline text editor for a sub-option field ─────────────────────────────
    edit_field() {
        local oi=$1
        local val="${OPT_VALS[$oi]}"
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
                    editing=false   # discard changes
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
```

- [ ] **Step 2: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "refactor(tui): update edit_field to use OPT_VALS and single panel"
```

---

### Task 7: Rewrite the main event loop

Replace the two-panel event loop with the new single-panel, accordion-aware loop.

**Files:**
- Modify: `robotics-setup.sh` — replace from `# ── Main event loop` through `_tui_cleanup`

- [ ] **Step 1: Replace the event loop**

```bash
    # ── Main event loop ────────────────────────────────────────────────────────
    while ! $done; do
        render_header
        render_panel

        # If confirmation overlay is open, handle it separately
        if $confirm_open; then
            render_confirm
            read_key
            case "$KEY" in
                ENTER|y|Y)
                    build_flat_list
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
                    # Jump cursor back to parent component row
                    local oi="${cur_entry#opt:}"
                    local parent_comp="${OPT_COMP[$oi]}"
                    # Find the comp:N entry index in flat list
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
                    # Collapse when turning off
                    (( !COMP_ON[ci] )) && expanded[$ci]=0
                    # Rebuild so cursor doesn't land on a now-hidden opt row
                    build_flat_list
                    n_rows=${#FLAT_LIST[@]}
                    (( cursor >= n_rows )) && cursor=$(( n_rows - 1 ))
                fi
                ;;

            ENTER)
                if [[ "$cur_entry" == opt:* ]]; then
                    local oi="${cur_entry#opt:}"
                    edit_field "$oi"
                elif [[ "$cur_entry" == "install" ]]; then
                    confirm_open=true
                fi
                # No-op on component rows
                ;;

            e|E)
                if $all_expanded; then
                    # Collapse all
                    local _i
                    for (( _i = 0; _i < n_comp; _i++ )); do expanded[$_i]=0; done
                    all_expanded=false
                else
                    # Expand all that are ON and have options
                    local _i
                    for (( _i = 0; _i < n_comp; _i++ )); do
                        (( COMP_ON[_i] && COMP_OPT_COUNT[_i] > 0 )) && expanded[$_i]=1
                    done
                    all_expanded=true
                fi
                ;;
        esac
    done

    _tui_cleanup
```

- [ ] **Step 2: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add robotics-setup.sh
git commit -m "feat(tui): rewrite event loop for single-panel accordion navigation"
```

---

### Task 8: Update apply-back logic and controls comment

Map `OPT_VALS` back to script variables (replacing the old `ADV_VALS` mapping), and update the controls comment at the top of the TUI section.

**Files:**
- Modify: `robotics-setup.sh:473-489` (apply-back block)
- Modify: `robotics-setup.sh:104-112` (controls comment)

- [ ] **Step 1: Replace the apply-back block**

Replace from `# ── Apply selections back to script variables` through `WS_DIR="${ADV_VALS[4]}"` with:

```bash
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

    # OPT_VALS order: ROS distro(0), Workspace(1), Agent ver(2), PX4 dir(3), venv dir(4)
    ROS_DISTRO="${OPT_VALS[0]}"
    WS_DIR="${OPT_VALS[1]}"
    UXRCE_AGENT_VERSION="${OPT_VALS[2]}"
    PX4_DIR="${OPT_VALS[3]}"
    VENV_DIR="${OPT_VALS[4]}"
```

Note: the old apply-back used `$(( COMP_ON[idx] == 1 && echo true || echo false))` which is broken (arithmetic context can't run `echo`). This replacement fixes it with a proper conditional.

- [ ] **Step 2: Update the controls comment block (lines 104-112)**

Replace:
```bash
# ─── Pure-Bash TUI (no whiptail / dialog / tput dependency) ──────────────────
#
#  Controls:
#   ↑ / ↓       move cursor
#   SPACE        toggle checkbox  (checklist panel)
#   ENTER        edit field value  (advanced panel) / confirm on summary screen
#   LEFT/RIGHT   switch between panels
#   q / ESC      quit / cancel
# ─────────────────────────────────────────────────────────────────────────────
```

With:
```bash
# ─── Pure-Bash TUI (no whiptail / dialog / tput dependency) ──────────────────
#
#  Controls:
#   ↑ / ↓       move cursor through all visible rows
#   →            expand component sub-options
#   ←            collapse component / jump to parent from sub-option
#   SPACE        toggle component on/off
#   ENTER        edit sub-option field / open install confirmation
#   E            expand all / collapse all
#   q / ESC      quit / cancel
# ─────────────────────────────────────────────────────────────────────────────
```

- [ ] **Step 3: Verify parsing**

```bash
bash -n robotics-setup.sh
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add robotics-setup.sh
git commit -m "fix(tui): update apply-back logic and controls comment for single-panel design"
```

---

### Task 9: Remove dead render calls and verify end-to-end

Clean up the now-removed `render_right_panel` and `render_status` call sites, then do a full manual run-through.

**Files:**
- Modify: `robotics-setup.sh` — verify no remaining references to removed symbols

- [ ] **Step 1: Check for dead references**

```bash
grep -n 'render_right_panel\|render_left_panel\|render_status\|r_cursor\|n_adv\|ADV_VALS\|ADV_LABELS\|panel=\|l_cursor\b' robotics-setup.sh
```

Expected: no matches. If any appear, remove them.

- [ ] **Step 2: Run the TUI manually**

```bash
bash robotics-setup.sh
```

Walk through each interaction and verify:
1. Default view shows 5 components with `>` on ROS, PX4, and Python venv; Gazebo and bashrc have no indicator
2. `↓` moves cursor down through components; `↑` moves back up
3. `>` (right arrow) on ROS expands it — two sub-option rows appear beneath it
4. `↓` moves into the sub-option rows; `<` (left arrow) returns cursor to ROS row without collapsing
5. `<` on the ROS row itself collapses the sub-options
6. `SPACE` on a component toggles its checkbox; toggling OFF immediately hides any expanded sub-options
7. `E` expands all components that are ON and have options; `E` again collapses all
8. Navigating to `[ Install ]` and pressing `ENTER` opens the confirmation overlay
9. Confirmation shows only enabled components, their size labels, total, available disk space, and estimated time
10. `Y` or `ENTER` proceeds to install (or shows insufficient space warning if disk is full)
11. `ESC` or `N` dismisses the overlay and returns to the component list
12. `ENTER` on a sub-option row opens inline edit; typing replaces the value; `ENTER` or `TAB` saves; `ESC` discards

- [ ] **Step 3: Final commit**

```bash
git add robotics-setup.sh
git commit -m "feat(tui): complete single-panel accordion TUI with install confirmation"
```
