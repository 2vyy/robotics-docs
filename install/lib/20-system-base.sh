# install/lib/20-system-base.sh — Step 0: locale and apt upgrade.

install_system_base() {
	if $DRY_RUN; then
		log_info "Dry-run mode: skipping system update & locale changes."
		return 0
	fi

	log_info "Setting up UTF-8 locale..."
	sudo apt-get update -qq
	sudo apt-get install -y -qq locales >/dev/null
	sudo locale-gen en_US.UTF-8 >/dev/null
	sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
	export LANG=en_US.UTF-8

	log_info "Consolidated apt update & upgrade..."
	sudo apt-get update -qq
	sudo apt-get upgrade -y -qq
}
