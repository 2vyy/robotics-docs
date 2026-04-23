# install/lib/90-post-install.sh — final messages (sourced by main.sh).

post_install() {
	log_step "Final Summary"

	if grep -qi microsoft /proc/version 2>/dev/null; then
		log_info "Detected WSL2 — install latest Windows GPU drivers + restart WSL for best performance."
	fi

	log_success "Installation complete! See the wiki for next steps:"
	if curl -fsS --max-time 2 http://localhost:4321/ >/dev/null 2>&1; then
		log_info "  - Verify your install: http://localhost:4321/onboarding/verify"
		log_info "  - First flight test:   http://localhost:4321/onboarding/px4-test"
	else
		log_info "  - Verify your install: /onboarding/verify (local docs: npm run dev)"
		log_info "  - First flight test:   /onboarding/px4-test"
	fi
	echo ""
}
