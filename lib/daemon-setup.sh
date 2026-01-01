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
    local download_url="https://github.com/lumopanel/daemon/releases/latest/download/lumo-daemon-linux-${arch}"

    if curl -fsSL -o /usr/bin/lumo-daemon "$download_url" 2>/dev/null; then
        chmod 755 /usr/bin/lumo-daemon
        log_success "Daemon binary downloaded"
    else
        log_warning "Could not download pre-built binary, attempting to build from source..."

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
                die "Could not clone daemon repository"
            fi
        else
            die "Could not download daemon and Rust is not installed. Please install manually: https://github.com/lumopanel/daemon/releases"
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
