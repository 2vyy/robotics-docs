# install/lib/08-phase-verify.sh — quick smoke checks after each install phase.
# Sourced after 00-common.sh; uses: DRY_RUN, ROS_DISTRO, PX4_DIR, WS_DIR, VENV_DIR, is_apt_installed.

verify_phase_preflight() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Pre-flight smoke check skipped"
		return 0
	fi
	[[ ${EUID:-0} -ne 0 ]] || {
		log_error "Must not run as root"
		exit 1
	}
	command -v apt-get >/dev/null || {
		log_error "apt-get not found"
		exit 1
	}
	local vid=""
	# shellcheck source=/dev/null
	vid="$(source /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}")"
	[[ "$vid" == "24.04" ]] || {
		log_error "Expected Ubuntu VERSION_ID 24.04, got '${vid:-}'"
		exit 1
	}
	log_success "Pre-flight OK (non-root, apt-get, Ubuntu ${vid})"
}

verify_phase_system_base() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 0 smoke check skipped"
		return 0
	fi
	local cm
	cm="$(LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null || true)"
	[[ "$cm" == "UTF-8" ]] || {
		log_error "locale charmap is '${cm:-}', expected UTF-8 (try: open a new terminal and re-run)"
		exit 1
	}
	log_success "Phase 0 OK (locale charmap UTF-8)"
}

verify_phase_ros_base() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 1 smoke check skipped"
		return 0
	fi
	[[ -f /etc/apt/sources.list.d/ros2.list ]] || {
		log_error "ROS 2 apt source missing: /etc/apt/sources.list.d/ros2.list"
		exit 1
	}
	command -v rosdep >/dev/null || {
		log_error "rosdep not on PATH"
		exit 1
	}
	command -v colcon >/dev/null || {
		log_error "colcon not on PATH"
		exit 1
	}
	log_success "Phase 1 OK (ros2.list, rosdep, colcon)"
}

verify_phase_ros_desktop() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 2 smoke check skipped"
		return 0
	fi
	if is_apt_installed "ros-${ROS_DISTRO}-desktop"; then
		log_success "Phase 2 OK (ros-${ROS_DISTRO}-desktop package installed)"
		return 0
	fi
	if [[ -d "/opt/ros/${ROS_DISTRO}" ]]; then
		log_success "Phase 2 OK (/opt/ros/${ROS_DISTRO} present)"
		return 0
	fi
	log_error "ROS 2 desktop not detected (no package ros-${ROS_DISTRO}-desktop, no /opt/ros/${ROS_DISTRO})"
	exit 1
}

verify_phase_gazebo() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 3 smoke check skipped"
		return 0
	fi
	if is_apt_installed "ros-${ROS_DISTRO}-ros-gz"; then
		log_success "Phase 3 OK (ros-${ROS_DISTRO}-ros-gz installed)"
		return 0
	fi
	command -v gz >/dev/null 2>&1 || {
		log_error "Gazebo (gz) not found on PATH after Phase 3"
		exit 1
	}
	log_success "Phase 3 OK (gz on PATH)"
}

verify_phase_px4() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 4 smoke check skipped"
		return 0
	fi
	[[ -f "${PX4_DIR}/build/px4_sitl_default/bin/px4" ]] || {
		log_error "PX4 SITL binary missing: ${PX4_DIR}/build/px4_sitl_default/bin/px4"
		exit 1
	}
	[[ -f /usr/local/bin/MicroXRCEAgent ]] || {
		log_error "MicroXRCEAgent missing under /usr/local/bin"
		exit 1
	}
	[[ -f "${WS_DIR}/install/setup.bash" ]] || {
		log_error "ROS workspace not built: ${WS_DIR}/install/setup.bash"
		exit 1
	}
	log_success "Phase 4 OK (px4 binary, MicroXRCEAgent, colcon install)"
}

verify_phase_pip() {
	robotics_phase_check_banner
	if $DRY_RUN; then
		log_success "[dry-run] Phase 5 smoke check skipped"
		return 0
	fi
	command -v uv >/dev/null || {
		log_error "uv not on PATH after Phase 5"
		exit 1
	}
	[[ -x "${VENV_DIR}/bin/python" ]] || {
		log_error "Python venv missing or not executable: ${VENV_DIR}/bin/python"
		exit 1
	}
	# One import that should exist if requirements installed (numpy is always listed).
	if ! "${VENV_DIR}/bin/python" -c "import numpy" 2>/dev/null; then
		log_error "venv python cannot import numpy (pip install phase incomplete?)"
		exit 1
	fi
	log_success "Phase 5 OK (uv, venv python, numpy import)"
}
