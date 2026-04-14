# TUI Inline Options Design

**Date:** 2026-04-14  
**Status:** Approved

## Overview

Collapse the existing two-panel layout (Components + Advanced Options) into a single panel where advanced options live as inline expandable sub-rows beneath their parent component. Remove the Advanced Options panel entirely. Add a navigable Install button and a confirmation overlay before any installation begins.

---

## Layout

### Single panel — default (collapsed) view

```
+--------------------------- Components ----------------------------+
| [✔] ROS 2 Jazzy Desktop                                       ▶  |
| [✔] Gazebo Harmonic                                               |
| [✔] PX4 SITL + uXRCE-DDS                                      ▶  |
| [✔] Python venv + packages                                     ▶  |
| [✔] Modify ~/.bashrc                                              |
|                                                                   |
|  [ Install ]                                                      |
| SPACE toggle  ↑↓ move  → expand  E expand all  ENTER install     |
+-------------------------------------------------------------------+
```

- The `▶` indicator appears only on components that have sub-options. Components without sub-options (Gazebo, bashrc) show no indicator.
- The box grows dynamically in height as components are expanded.
- The `[ Install ]` button is a selectable row at the bottom of the list, navigable with `↑↓`.

### Expanded view (after pressing `→` on PX4)

```
+--------------------------- Components ----------------------------+
| [✔] ROS 2 Jazzy Desktop                                       ▶  |
| [✔] Gazebo Harmonic                                               |
| [✔] PX4 SITL + uXRCE-DDS                                      ▼  |
|      ▸ Agent ver  [v2.2.1                                      ]  |
|      ▸ PX4 dir   [~/PX4-Autopilot                              ]  |
| [✔] Python venv + packages                                     ▶  |
| [✔] Modify ~/.bashrc                                              |
|                                                                   |
|  [ Install ]                                                      |
| SPACE toggle  ↑↓ move  ← back  ENTER edit  E collapse all        |
+-------------------------------------------------------------------+
```

---

## Component → Sub-option Mapping

| Component           | Sub-options                        |
|---------------------|------------------------------------|
| ROS 2 Jazzy Desktop | ROS distro, Workspace dir          |
| Gazebo Harmonic     | *(none)*                           |
| PX4 SITL + uXRCE   | Agent ver, PX4 dir                 |
| Python venv         | venv dir                           |
| Modify ~/.bashrc    | *(none)*                           |

---

## Key Bindings

| Key         | Action                                                                                 |
|-------------|----------------------------------------------------------------------------------------|
| `↑` / `↓`  | Move cursor through all visible rows as a flat list (component rows + sub-option rows) |
| `→`         | Expand the focused component (show sub-options). No-op if no options or already open.  |
| `←`         | If on a component row: collapse it. If on a sub-option row: jump cursor to parent component row (does not collapse it). |
| `SPACE`     | On a component row: toggle on/off (collapsing and hiding sub-options when turned off)  |
| `ENTER`     | On a sub-option row: enter inline edit mode. On Install button: open confirmation. No-op on component rows. |
| `E`         | Toggle expand-all / collapse-all                                                       |
| `q` / `ESC` | Cancel and exit                                                                        |

---

## Expand/Collapse Behaviour

- `▶` = component has sub-options, currently collapsed
- `▼` = component has sub-options, currently expanded
- No indicator = component has no sub-options (Gazebo, bashrc)
- When `E` is pressed: hint text toggles between "E expand all" and "E collapse all"
- When a component is toggled **off** with `SPACE`: its sub-option rows are immediately hidden (as if collapsed). The expand indicator is also hidden since there is nothing to configure for a disabled component.
- Sub-option values are preserved when a component is toggled off and back on.

---

## Install Button & Confirmation Overlay

### Install button

A selectable row at the bottom of the component list, styled distinctly (e.g. `[ Install ]`). Reached by navigating down past all component/sub-option rows. Pressing `ENTER` opens the confirmation overlay. `SPACE` has no effect on the Install button row.

### Confirmation overlay

A centred box drawn over the dimmed component panel:

```
+---------- Confirm Installation ----------+
| The following will be installed:         |
|                                          |
|  ✔ ROS 2 Jazzy Desktop       ~4.2 GB    |
|  ✔ Gazebo Harmonic            ~1.8 GB   |
|  ✔ PX4 SITL + uXRCE-DDS      ~2.1 GB   |
|  ✔ Python venv + packages     ~0.3 GB   |
|  ✔ Modify ~/.bashrc           —         |
|                                          |
|  Total storage:  ~8.4 GB                 |
|  Available:      142 GB       OK         |
|  Est. time:      ~25 min                 |
|                                          |
|   [ Y / ENTER  Confirm ]   ESC / N back  |
+------------------------------------------+
```

**Storage estimates:** Hardcoded per-component constants (placeholder values — to be updated with accurate figures). Displayed with `~` prefix to set approximate expectations.

**Disk space check:** Run `df -k "$HOME"` at the time the confirmation overlay opens. Compare available KB against the sum of enabled components' size estimates. If available space is less than required:
- Show available space in **red**
- Add a warning line: `  !! Insufficient disk space`
- Disable the Confirm option (pressing Y/ENTER shows the warning but does not proceed)

**Only enabled components appear** in the confirmation list. Components toggled off are omitted entirely.

**Y or ENTER** confirms and begins installation. **ESC or N** dismisses the overlay and returns focus to the component list with all state preserved.

---

## State Model

```
flat_list[]        — ordered list of all currently visible rows
                     (component rows + expanded sub-option rows + Install button)
cursor             — index into flat_list
expanded{}         — set of component indices that are currently open
all_expanded       — bool, tracks E toggle state
editing            — bool, true when inline field editor is active
confirm_open       — bool, true when confirmation overlay is shown
```

The flat list is recomputed on every render based on `COMP_ON[]` and `expanded{}`.

---

## Removed

- Right panel (`render_right_panel`, `panel` state variable, `r_cursor`, left/right panel-switching logic)
- `TAB` key binding
- Status bar "Will install: …" line (replaced by confirmation overlay)
