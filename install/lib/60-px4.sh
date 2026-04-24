# install/lib/60-px4.sh — Step 4: PX4 SITL, Micro XRCE-DDS agent, px4_msgs workspace.

build_xrce_agent() {
	local temp_agent="/tmp/XRCE-Agent"
	if [[ -d "${temp_agent}" ]]; then
		run_cmd rm -rf "${temp_agent}"
	fi
	run_cmd git clone -b "${UXRCE_AGENT_VERSION}" https://github.com/eProsima/Micro-XRCE-DDS-Agent.git "${temp_agent}"
	run_cmd cmake -S "${temp_agent}" -B "${temp_agent}/build"
	run_cmd make -C "${temp_agent}/build" -j"$(nproc)"
	run_cmd sudo make -C "${temp_agent}/build" install
	run_cmd sudo ldconfig /usr/local/lib/
}

install_px4() {
	if [[ -d "${PX4_DIR}/.git" ]]; then
		log_info "PX4 already present at ${PX4_DIR}"
		run_cmd git -C "${PX4_DIR}" pull --rebase || true
	else
		run_cmd git clone --recursive https://github.com/PX4/PX4-Autopilot.git "${PX4_DIR}"
	fi

	log_info "Ensuring PX4 dependencies (ubuntu.sh)..."
	run_cmd bash "${PX4_DIR}/Tools/setup/ubuntu.sh" --no-nuttx

	if $REBUILD || [[ ! -f "${PX4_DIR}/build/px4_sitl_default/bin/px4" ]]; then
		log_info "Building PX4 SITL (this may take 10+ min)..."
		run_cmd make -C "${PX4_DIR}" px4_sitl
	else
		log_info "PX4 SITL already built — skipping (use --rebuild to force)"
	fi

	if [[ ! -f /usr/local/bin/MicroXRCEAgent ]]; then
		log_info "Building Micro XRCE-DDS Agent ${UXRCE_AGENT_VERSION}..."
		build_xrce_agent
	fi

	mkdir -p "${WS_DIR}/src"
	if [[ ! -d "${WS_DIR}/src/px4_msgs" ]]; then
		run_cmd git -C "${WS_DIR}/src" clone https://github.com/PX4/px4_msgs.git
	fi

	if $REBUILD || [[ ! -f "${WS_DIR}/install/setup.bash" ]]; then
		log_info "Building ROS 2 workspace..."
		if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
			# shellcheck source=/dev/null
			if ! source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null; then
				log_warn "Could not source /opt/ros/${ROS_DISTRO}/setup.bash before colcon; build may fail—open a new terminal and re-run if needed."
			fi
		fi
		run_cmd colcon build --symlink-install \
			--base-paths "${WS_DIR}/src" \
			--build-base "${WS_DIR}/build" \
			--install-base "${WS_DIR}/install"
	fi
	bashrc_append "source ${WS_DIR}/install/setup.bash"
}
