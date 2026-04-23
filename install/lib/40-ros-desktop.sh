# install/lib/40-ros-desktop.sh — Step 2: ROS 2 desktop metapackage.

install_ros_desktop() {
	if is_apt_installed "ros-${ROS_DISTRO}-desktop"; then
		log_info "ros-${ROS_DISTRO}-desktop already installed ✓"
	else
		run_cmd sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
	fi
	bashrc_append "source /opt/ros/${ROS_DISTRO}/setup.bash"
	# shellcheck source=/dev/null
	source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null || true
}
