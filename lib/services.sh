#!/usr/bin/env bash
#
# Systemd service management functions
#

[[ -n "${_SERVICES_SH_LOADED:-}" ]] && return 0
readonly _SERVICES_SH_LOADED=1

# =============================================================================
# Horizon Service
# =============================================================================

create_horizon_service() {
    log_step "Creating Horizon systemd service"

    render_template_to_file "lumo-horizon.service" "/etc/systemd/system/lumo-horizon.service" "root" "root" "0644"

    add_cleanup_task "rm -f /etc/systemd/system/lumo-horizon.service"

    systemctl daemon-reload

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_enable "lumo-horizon" || systemctl enable lumo-horizon
    else
        systemctl enable lumo-horizon
    fi

    log_success "Horizon service created"
}

# =============================================================================
# Scheduler (Cron)
# =============================================================================

setup_scheduler() {
    log_step "Setting up Laravel scheduler"

    # Log to a file instead of discarding output
    local log_file="${INSTALL_DIR}/storage/logs/scheduler.log"
    local cron_entry="* * * * * cd ${INSTALL_DIR} && php artisan schedule:run >> ${log_file} 2>&1"

    if ! crontab -u "$LUMO_USER" -l 2>/dev/null | grep -q "artisan schedule:run"; then
        (crontab -u "$LUMO_USER" -l 2>/dev/null || true; echo "$cron_entry") | crontab -u "$LUMO_USER" -
        log_success "Scheduler cron job added for ${LUMO_USER}"
    else
        log_info "Scheduler cron job already exists"
    fi

    # Ensure log file exists and is writable
    touch "$log_file" 2>/dev/null || true
    chown "${LUMO_USER}:${LUMO_GROUP}" "$log_file" 2>/dev/null || true
}

# =============================================================================
# Start Services
# =============================================================================

start_services() {
    log_step "Starting services"

    # Daemon should already be running
    if systemctl is-active --quiet lumo-daemon; then
        log_success "Daemon is running"
    else
        log_warning "Daemon is not running, attempting to start..."
        if [[ "$USE_DAEMON" == "true" ]]; then
            daemon_service_start "lumo-daemon" || systemctl start lumo-daemon || log_error "Could not start daemon"
        else
            systemctl start lumo-daemon || log_error "Could not start daemon"
        fi
    fi

    # Start Horizon
    if [[ -f "${INSTALL_DIR}/artisan" ]]; then
        if [[ "$USE_DAEMON" == "true" ]]; then
            daemon_service_start "lumo-horizon" && log_success "Horizon started" || {
                systemctl start lumo-horizon 2>/dev/null && log_success "Horizon started" || log_warning "Could not start Horizon"
            }
        else
            systemctl start lumo-horizon 2>/dev/null && log_success "Horizon started" || log_warning "Could not start Horizon"
        fi
    fi

    log_success "All services started"
}
