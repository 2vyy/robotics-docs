# install/lib/10-preflight.sh — pre-install checks (sourced by main.sh).

robotics_run_preflight() {
	if $DRY_RUN; then
		log_warn "DRY RUN MODE — no changes will be made to your system."
	fi

	if [[ $EUID -eq 0 ]]; then
		log_error "This script should NOT be run with sudo or as root."
		exit 1
	fi

	if $INSTALL_ROS_BASE; then
		check_target_space "/" 15 "ROS/Gazebo apt packages"
	fi
	if $INSTALL_PX4; then
		check_target_space "${PX4_DIR}" 10 "PX4 source/build"
		check_target_space "${WS_DIR}" 4 "ROS workspace"
	fi
	if $INSTALL_PIP; then
		check_target_space "${VENV_DIR}" 2 "Python venv"
	fi

	local RAM_TOTAL
	RAM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
	log_info "Total RAM: ${RAM_TOTAL} (use 'free -h' for details) ✓"

	# OS gate is enforced at startup in main.sh (robotics_require_ubuntu_24_04); re-assert if this file is ever sourced alone.
	robotics_require_ubuntu_24_04 || exit 1
}
