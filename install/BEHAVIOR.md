# Installer behavior checklist

This document is the contract for the modular installer (`install/main.sh` and `install/lib/*.sh`). It matches the legacy monolith’s intent; change it when you intentionally change behavior.

## Environment

- Target: **online official Ubuntu 24.04 LTS (Noble)** only: `/etc/os-release` must have `ID=ubuntu`, `VERSION_ID=24.04`, and `VERSION_CODENAME=noble`. Enforced in `bootstrap.sh` and `main.sh` before any downloads or `tee` logging.
- **Not** run as root (no `sudo` on the script itself; the script invokes `sudo` for apt).
- Idempotent: safe to re-run with partial installs.
- Before tagging a ref for a class, run a smoke test on a **clean** 24.04 VM (partial-install re-runs are harder to simulate automatically).

## Entry points


| Path                  | Use                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| `curl … | bash`       | Runs `[bootstrap.sh](./bootstrap.sh)`: downloads pinned `install/*.sh` from GitHub raw, then `main.sh`. |
| `./install/main.sh`   | Local git checkout: sources `lib/*.sh` from the same tree.                                              |
| `./robotics-setup.sh` | Thin wrapper at repo root → `install/main.sh` (same flags).                                             |


## TUI (plan option B)

- If **no arguments** and **stdin is a TTY**, an interactive TUI runs first (same flow as the legacy script). Plain `curl … | bash` would leave stdin as a pipe, so **`bootstrap.sh` runs `main.sh` with `</dev/tty`** when `/dev/tty` is available so the TUI still works from a one-liner.
- If stdin is **not** a TTY (e.g. `curl \| bash`), defaults stay **full install** (`INSTALL_ROS`, `INSTALL_GAZEBO`, `INSTALL_PX4`, `INSTALL_PIP` all true) with a short countdown before starting.

## TTY phase headers

- Before `exec … tee`, `main.sh` records whether **stdout was a TTY** in `ROBOTICS_CLI_TTY` (because the pipe to `tee` would otherwise hide interactivity).
- When `ROBOTICS_CLI_TTY=1`, each phase prints an extra **banner and bullet plan** (what the phase will do) in addition to the normal `[INFO]` / `▶ Phase …` lines.

## Post-phase smoke checks

After each phase (and after pre-flight), `lib/08-phase-verify.sh` runs a **small non-destructive check** (e.g. `locale charmap`, `ros2.list` present, `import numpy` in the venv). On failure the script exits non-zero. `--dry-run` skips substantive checks and logs a skip line instead.

## Flags (CLI)

Same semantics as the legacy `robotics-setup.sh`:

- Components: `--full`, `--ros-only`, `--gazebo-only`, `--px4-only`, `--pip-only`, `--no-ros`, `--no-gazebo`, `--no-px4`, `--no-pip`.
- Other: `--no-bashrc`, `--rebuild`, `--dry-run`, `--no-color`, `--pip-alias`, `--compile-reqs`.
- Parameters: `--ros-distro`, `--agent-ver`, `--px4-dir`, `--venv-dir`, `--ws-dir`.
- `--help` prints usage and exits.

## Ordered phases

`INSTALL_ROS_BASE` is true if any of ROS desktop, Gazebo, PX4, or Pip is enabled (ROS apt repo + colcon/rosdep are shared).


| Order | Phase                                                        | Function                 | Skip when                         |
| ----- | ------------------------------------------------------------ | ------------------------ | --------------------------------- |
| pre   | Disk / OS / root checks                                      | `robotics_run_preflight` | Never                             |
| 0     | System locale + apt upgrade                                  | `install_system_base` | Never (no-op body in `--dry-run`) |
| 1     | ROS repo + dev tools + rosdep                                | `install_ros_base`    | `INSTALL_ROS_BASE` is false       |
| 2     | ROS 2 desktop metapackage                                    | `install_ros_desktop` | `INSTALL_ROS` is false            |
| 3     | Gazebo / ros_gz + vendors                                    | `install_gazebo`      | `INSTALL_GAZEBO` is false         |
| 4     | PX4 clone, ubuntu.sh, build, XRCE agent, `px4_msgs` + colcon | `install_px4`         | `INSTALL_PX4` is false            |
| 5     | uv, venv, requirements, optional pip-audit                   | `install_pip`         | `INSTALL_PIP` is false            |
| —     | Summary + wiki hints                                         | `post_install`        | Always                            |


## Idempotency notes

- **Apt:** Skip desktop install if `ros-${ROS_DISTRO}-desktop` is already installed; skip `ros-gz` if present; ros2.list/ros key only added if missing.
- **PX4:** If `${PX4_DIR}/.git` exists, `git pull --rebase`; else clone. Build skipped if `build/px4_sitl_default/bin/px4` exists unless `--rebuild`.
- **MicroXRCEAgent:** Skip build if `/usr/local/bin/MicroXRCEAgent` exists.
- **Workspace:** Clone `px4_msgs` only if missing; `colcon build` skipped if `install/setup.bash` exists unless `--rebuild`.
- **Python:** Skip `uv` install if on PATH; skip `uv venv` if `${VENV_DIR}` exists; requirements rewritten each run (same content).

## Defaults

- `ROS_DISTRO=jazzy`, `UBUNTU_CODENAME=noble`, `UXRCE_AGENT_VERSION=v2.4.3`
- `PX4_DIR=~/PX4-Autopilot`, `WS_DIR=~/ros2_ws`, `VENV_DIR=~/ros2_venv`
- `MODIFY_BASHRC=true` unless `--no-bashrc`

## On failure

Non-zero exit; messages reference wiki path `/onboarding/troubleshooting` (no assumption that the local docs dev server is running).