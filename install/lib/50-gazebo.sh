# install/lib/50-gazebo.sh — Step 3: Gazebo Harmonic + ROS integration.

install_gazebo() {
	# shellcheck source=/dev/null
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
