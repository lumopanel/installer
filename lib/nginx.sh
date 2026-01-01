#!/usr/bin/env bash
#
# Nginx configuration functions
#

[[ -n "${_NGINX_SH_LOADED:-}" ]] && return 0
readonly _NGINX_SH_LOADED=1

# =============================================================================
# Nginx Configuration
# =============================================================================

configure_nginx() {
    log_step "Configuring Nginx"

    # Add nginx user to lumo group so it can read static files
    add_user_to_group www-data "$LUMO_GROUP"

    # Remove default site using daemon if available
    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_nginx_disable_site "default" || rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    else
        rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    fi

    # Render and write nginx site configuration
    render_template_to_file "nginx-site.conf" "/etc/nginx/sites-available/lumo" "root" "root" "0644"

    # Enable site
    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_nginx_enable_site "lumo" || ln -sf /etc/nginx/sites-available/lumo /etc/nginx/sites-enabled/lumo
    else
        ln -sf /etc/nginx/sites-available/lumo /etc/nginx/sites-enabled/lumo
    fi

    # Test and reload configuration
    local config_valid=false

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_nginx_test_config && config_valid=true
    fi

    if [[ "$config_valid" != "true" ]]; then
        nginx -t 2>&1 && config_valid=true
    fi

    if [[ "$config_valid" == "true" ]]; then
        if [[ "$USE_DAEMON" == "true" ]]; then
            daemon_service_reload "nginx" || systemctl reload nginx
        else
            systemctl reload nginx
        fi
        log_success "Nginx configured"
    else
        die "Nginx configuration test failed"
    fi
}

# =============================================================================
# PHP-FPM Pool Configuration
# =============================================================================

configure_php_fpm_pool() {
    log_info "Creating PHP-FPM pool for ${LUMO_USER} user..."

    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/${LUMO_USER}.conf"

    # Create tmp directory for uploads
    mkdir -p "${INSTALL_DIR}/storage/app/tmp" 2>/dev/null || true
    chown "${LUMO_USER}:${LUMO_GROUP}" "${INSTALL_DIR}/storage/app/tmp" 2>/dev/null || true

    # Render and write pool configuration
    render_template_to_file "php-fpm-pool.conf" "$pool_conf" "root" "root" "0644"

    # Restart PHP-FPM to load new pool
    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_restart "php${PHP_VERSION}-fpm" || systemctl restart "php${PHP_VERSION}-fpm"
    else
        systemctl restart "php${PHP_VERSION}-fpm"
    fi

    log_success "PHP-FPM pool created for ${LUMO_USER}"
}
