#!/usr/bin/env bash
#
# Daemon installation and configuration
#

[[ -n "${_DAEMON_SETUP_SH_LOADED:-}" ]] && return 0
readonly _DAEMON_SETUP_SH_LOADED=1

# =============================================================================
# Daemon Installation
# =============================================================================

install_daemon() {
    log_step "Installing Lumo Daemon"

    # Ensure lumo user exists before setting up directories
    ensure_lumo_user

    # Create directories with proper permissions
    mkdir -p "$DAEMON_CONFIG_DIR/templates"
    mkdir -p "$DAEMON_SOCKET_DIR"
    mkdir -p "$DAEMON_LOG_DIR"
    mkdir -p "$DAEMON_TEMPLATES_DIR"

    # Socket directory permissions - root owns, www-data group for nginx access
    chown "root:www-data" "$DAEMON_SOCKET_DIR"
    chmod 755 "$DAEMON_SOCKET_DIR"

    add_cleanup_task "rm -rf $DAEMON_CONFIG_DIR $DAEMON_SOCKET_DIR $DAEMON_LOG_DIR"

    log_info "Downloading Lumo Daemon..."

    local arch
    arch=$(uname -m)

    # Map architecture names
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        arm64)   arch="aarch64" ;;
        *)       die "Unsupported architecture: $arch" ;;
    esac

    local download_url="https://github.com/lumopanel/daemon/releases/latest/download/lumo-daemon-${arch}-linux.tar.gz"
    local temp_tar="/tmp/lumo-daemon.tar.gz"

    log_info "Download URL: $download_url"
    log_info "Architecture: $arch"

    local curl_exit_code
    local curl_output
    curl_output=$(curl -fsSL -o "$temp_tar" -w "%{http_code}" "$download_url" 2>&1) || curl_exit_code=$?

    if [[ -z "${curl_exit_code:-}" ]] && [[ -f "$temp_tar" ]] && [[ -s "$temp_tar" ]]; then
        # Extract binary from tarball
        if tar -xzf "$temp_tar" -C /usr/bin/ 2>&1; then
            rm -f "$temp_tar"
            chmod 755 /usr/bin/lumo-daemon
            log_success "Daemon binary downloaded and extracted"
        else
            rm -f "$temp_tar"
            log_error "Failed to extract daemon tarball"
            die "The downloaded file may be corrupted or in an unexpected format"
        fi
    else
        log_warning "Could not download pre-built binary"
        log_warning "  URL: $download_url"
        log_warning "  Architecture: $arch (from uname -m: $(uname -m))"
        log_warning "  HTTP response: ${curl_output:-unknown}"
        log_warning "  Curl exit code: ${curl_exit_code:-0}"
        rm -f "$temp_tar" 2>/dev/null || true

        log_info "Attempting to build from source..."

        if command_exists cargo; then
            log_info "Rust found, building daemon from source..."

            local temp_dir
            temp_dir=$(mktemp -d)
            add_cleanup_task "rm -rf $temp_dir"

            if git clone --depth 1 --branch "$DAEMON_VERSION" https://github.com/lumopanel/daemon.git "$temp_dir" 2>/dev/null; then
                (cd "$temp_dir" && cargo build --release)
                cp "$temp_dir/target/release/lumo-daemon" /usr/bin/lumo-daemon
                chmod 755 /usr/bin/lumo-daemon
                rm -rf "$temp_dir"
                log_success "Daemon built from source"
            else
                die "Could not clone daemon repository from https://github.com/lumopanel/daemon.git (branch: $DAEMON_VERSION)"
            fi
        else
            log_error "Rust/Cargo is not installed, cannot build from source"
            log_error ""
            log_error "To fix this, either:"
            log_error "  1. Download the daemon manually from: https://github.com/lumopanel/daemon/releases"
            log_error "  2. Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            log_error ""
            log_error "Expected binary URL: $download_url"
            die "Daemon installation failed"
        fi
    fi

    add_cleanup_task "rm -f /usr/bin/lumo-daemon"

    log_success "Daemon binary installed"
}

# =============================================================================
# Daemon Configuration
# =============================================================================

configure_daemon() {
    log_step "Configuring Lumo Daemon"

    # Generate HMAC secret (base64 encoded per daemon documentation)
    log_info "Generating HMAC secret..."
    HMAC_SECRET_PATH="${DAEMON_CONFIG_DIR}/hmac.key"

    # Check for existing secret (idempotency)
    if [[ -f "$HMAC_SECRET_PATH" ]]; then
        log_info "Using existing HMAC secret"
        HMAC_SECRET=$(cat "$HMAC_SECRET_PATH")
    else
        # Generate base64-encoded secret (per daemon docs: openssl rand -base64 32)
        HMAC_SECRET=$(openssl rand -base64 32)
        echo -n "$HMAC_SECRET" > "$HMAC_SECRET_PATH"
    fi

    chmod 600 "$HMAC_SECRET_PATH"
    chown root:root "$HMAC_SECRET_PATH"

    # Export for use in panel .env (already base64)
    DAEMON_SECRET="$HMAC_SECRET"

    # Render daemon configuration
    render_template_to_file "daemon.toml" "${DAEMON_CONFIG_DIR}/daemon.toml" "root" "root" "0600"

    log_success "Daemon configuration created"
}

# =============================================================================
# Daemon Service
# =============================================================================

create_daemon_service() {
    log_step "Creating Daemon systemd service"

    copy_template "lumo-daemon.service" "/etc/systemd/system/lumo-daemon.service" "root" "root" "0644"

    add_cleanup_task "rm -f /etc/systemd/system/lumo-daemon.service"

    systemctl daemon-reload
    systemctl enable lumo-daemon
    systemctl start lumo-daemon

    log_success "Daemon systemd service created and started"
}
