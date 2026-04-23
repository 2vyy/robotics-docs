# install/lib/70-python.sh — Step 5: uv, venv, pip packages (sourced by main.sh).
# Expects: REQUIREMENTS_FILE, INSTALL_CACHE (set by main.sh).

write_requirements() {
	if $DRY_RUN; then
		echo -e "${YELLOW}[DRY-RUN]${NC} Write ${REQUIREMENTS_FILE}"
		return 0
	fi

	mkdir -p "$(dirname "${REQUIREMENTS_FILE}")"
	cat >"${REQUIREMENTS_FILE}" <<'REQUIREMENTS_EOF'
# ROS 2 Robotics Wiki - Core Python Dependencies
# Optimized for ROS 2 Jazzy on Ubuntu 24.04

# Scientific Computing
numpy
scipy
matplotlib
pandas

# Computer Vision
opencv-python-headless

# Robotics Math & Transforms
pyyaml
transforms3d
pyquaternion

# MAVLink & PX4 Integration
mavsdk
pymavlink

# Testing & Quality Assurance
pytest
pytest-cov
pre-commit

# Build Tools & Generators
# NOTE: empy must be version 3.x for PX4 compatibility
empy==3.3.4
jinja2
toml
jsonschema
future
kconfiglib
packaging
REQUIREMENTS_EOF
}

requirements_have_hashes() {
	local req_file="$1"
	grep -Eq '^[[:space:]]*[^#].*--hash=' "$req_file"
}

compute_uv_exclude_newer() {
	date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ'
}

configure_uv_defaults() {
	local exclude_newer
	exclude_newer="$(compute_uv_exclude_newer)"
	export UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER:-$exclude_newer}"

	local uv_config_dir="$HOME/.config/uv"
	local uv_config_file="${uv_config_dir}/uv.toml"
	if [[ -f "${uv_config_file}" ]]; then
		log_info "Global uv config already exists at ${uv_config_file}"
		return 0
	fi

	if $DRY_RUN; then
		echo -e "${YELLOW}[DRY-RUN]${NC} Write ${uv_config_file} with exclude-newer=${exclude_newer}"
		return 0
	fi

	mkdir -p "${uv_config_dir}"
	cat >"${uv_config_file}" <<EOF
exclude-newer = "${exclude_newer}"
EOF
	log_info "Created global uv config at ${uv_config_file}"
}

install_uv() {
	if command -v uv &>/dev/null; then
		log_info "uv already installed: $(uv --version) ✓"
	else
		log_info "Installing uv (package manager)..."
		run_cmd curl -LsSf https://astral.sh/uv/install.sh | sh
		export PATH="$HOME/.local/bin:$PATH"
		bashrc_append 'export PATH="$HOME/.local/bin:$PATH"'
	fi

	configure_uv_defaults

	log_info "Installing standalone CLI tools (ruff, ty, just) via uv tool..."
	if command -v ruff &>/dev/null; then
		log_info "ruff already available ✓"
	else
		run_cmd env UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER}" uv tool install ruff
	fi
	if command -v ty &>/dev/null; then
		log_info "ty already available ✓"
	else
		run_cmd env UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER}" uv tool install ty
	fi
	if command -v just &>/dev/null; then
		log_info "just already available ✓"
	else
		run_cmd env UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER}" uv tool install rust-just
	fi
}

compile_requirements() {
	log_info "Compiling hashed requirements (uv pip compile)…"

	if [[ ! -f "${REQUIREMENTS_FILE}" ]]; then
		if $DRY_RUN; then
			echo -e "${YELLOW}[DRY-RUN]${NC} Compile ${REQUIREMENTS_FILE} with hashes"
			return 0
		fi
		log_error "${REQUIREMENTS_FILE} not found! Cannot compile."
		return 1
	fi

	log_info "Compiling ${REQUIREMENTS_FILE} with hashes..."
	run_cmd uv pip compile --generate-hashes "${REQUIREMENTS_FILE}" -o "${REQUIREMENTS_FILE}"
}

install_pip() {
	install_uv
	write_requirements

	if $COMPILE_REQS; then
		compile_requirements
	fi

	log_info "Setting up Python dependencies with uv pip"

	if [[ ! -d "${VENV_DIR}" ]]; then
		log_info "Creating virtual environment at ${VENV_DIR}..."
		run_cmd uv venv --seed --system-site-packages --python python3 "${VENV_DIR}"
	fi

	log_info "Installing pip-audit into venv for vulnerability scanning (best-effort)..."
	run_cmd uv pip install --python "${VENV_DIR}/bin/python" --upgrade pip-audit || log_warn "Failed to install pip-audit; continuing without audit"

	if [[ -f "${REQUIREMENTS_FILE}" ]]; then
		log_info "Installing pip packages from ${REQUIREMENTS_FILE} using uv..."

		if requirements_have_hashes "${REQUIREMENTS_FILE}"; then
			run_cmd env UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER}" uv pip install --python "${VENV_DIR}/bin/python" --require-hashes -r "${REQUIREMENTS_FILE}"
			log_info "Installed packages using --require-hashes"
		else
			log_warn "${REQUIREMENTS_FILE} is not fully hash-pinned; installing without --require-hashes."
			run_cmd env UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER}" uv pip install --python "${VENV_DIR}/bin/python" -r "${REQUIREMENTS_FILE}"
		fi

		if [[ -x "${VENV_DIR}/bin/pip-audit" ]]; then
			log_info "Running pip-audit to scan installed packages (best-effort)..."
			if ! run_cmd "${VENV_DIR}/bin/pip-audit"; then
				log_warn "pip-audit reported issues or failed. Please review the above output."
			else
				log_info "pip-audit completed with no findings."
			fi
		else
			log_warn "pip-audit not available; skipping vulnerability scan."
		fi

	else
		log_warn "${REQUIREMENTS_FILE} not found! Skipping pip packages."
	fi

	if $SET_PIP_ALIAS && $MODIFY_BASHRC && ! $DRY_RUN; then
		bashrc_append 'alias pip='\''echo -e "\033[0;36m* pip aliased to uv pip. To use system pip, use \033[1mcommand pip\033[0m" && uv pip'\'''
		log_info "Added alias pip='uv pip' (with reminder) to ~/.bashrc"
	fi

	bashrc_append "source ${VENV_DIR}/bin/activate"
}
