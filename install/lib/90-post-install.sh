# install/lib/90-post-install.sh — final messages (sourced by main.sh).

post_install() {
	log_step "Final summary — what ran this session"

	log_info "Component flags (what this run attempted):"
	log_info "  ROS 2 desktop:              $($INSTALL_ROS && echo yes || echo no)"
	log_info "  Gazebo (ros_gz):            $($INSTALL_GAZEBO && echo yes || echo no)"
	log_info "  PX4 SITL + XRCE + msgs ws: $($INSTALL_PX4 && echo yes || echo no)"
	log_info "  Python venv (uv + reqs):    $($INSTALL_PIP && echo yes || echo no)"
	log_info "  Append to ~/.bashrc:        $($MODIFY_BASHRC && echo yes || echo no)"
	if $INSTALL_ROS_BASE; then
		log_info "  ROS apt base (repos/tools): yes (required for at least one component above)"
	else
		log_info "  ROS apt base:               no (nothing requested that needs it)"
	fi

	log_info "Key paths:"
	if $INSTALL_ROS_BASE; then
		log_info "  ROS 2 (apt):      /opt/ros/${ROS_DISTRO}"
	fi
	if $INSTALL_GAZEBO; then
		log_info "  Gazebo:           GZ_VERSION=harmonic (see ~/.bashrc if enabled)"
	fi
	if $INSTALL_PX4; then
		log_info "  PX4 source:       ${PX4_DIR}"
		log_info "  ROS workspace:    ${WS_DIR}"
		log_info "  XRCE agent:       /usr/local/bin/MicroXRCEAgent"
	fi
	if $INSTALL_PIP; then
		log_info "  Python venv:      ${VENV_DIR}"
	fi
	log_info "  Full transcript:  ${LOGFILE:-$HOME/ros2-jazzy-install.log}"

	if grep -qi microsoft /proc/version 2>/dev/null; then
		log_info "Detected WSL2 — install latest Windows GPU drivers + restart WSL for best Gazebo performance."
	fi

	log_success "Installation finished. Load your shell config (new terminal or: source ~/.bashrc), then:"
	if curl -fsS --max-time 2 http://localhost:4321/ >/dev/null 2>&1; then
		log_info "  Verify:  http://localhost:4321/onboarding/verify"
		log_info "  PX4 sim: http://localhost:4321/onboarding/px4-test"
	else
		log_info "  Verify:  https://github.com/2vyy/robotics-docs (wiki path /onboarding/verify)"
		log_info "  PX4 sim: same repo — /onboarding/px4-test"
	fi
	echo ""
	ROBOTICS_INSTALL_COMPLETE=1
}
