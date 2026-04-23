# install/lib/30-ros-base.sh — Step 1: ROS 2 apt repo and dev tools.

install_ros_base() {
	run_cmd sudo apt-get install -y -qq build-essential cmake curl git gnupg lsb-release wget software-properties-common

	if [[ ! -f /etc/apt/sources.list.d/ros2.list ]]; then
		log_info "Adding ROS 2 apt repository..."
		run_cmd sudo add-apt-repository -y universe
		run_cmd sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
		if $DRY_RUN; then
			echo -e "${YELLOW}[DRY-RUN]${NC} Write /etc/apt/sources.list.d/ros2.list for ROS 2 apt source"
		else
			echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main" |
				sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
		fi
		run_cmd sudo apt-get update -qq
	fi

	log_info "Installing ROS 2 development tools..."
	run_cmd sudo apt-get install -y -qq \
		python3-colcon-common-extensions python3-rosdep python3-vcstool \
		python3-argcomplete ros-dev-tools

	if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
		run_cmd sudo rosdep init || true
	fi
	if ! run_cmd rosdep update --rosdistro="${ROS_DISTRO}"; then
		log_warn "rosdep update failed (often transient network or proxy issues on first run); continuing."
	fi
}
