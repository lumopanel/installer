#!/usr/bin/env bash
#
# SSL/TLS configuration functions
#

[[ -n "${_SSL_SH_LOADED:-}" ]] && return 0
readonly _SSL_SH_LOADED=1

# =============================================================================
# SSL Setup (using daemon webroot method)
# =============================================================================

setup_ssl() {
    log_step "Setting up SSL with Let's Encrypt"

    if [[ "$SKIP_SSL" == "true" ]]; then
        log_warning "Skipping SSL setup as requested"
        return 0
    fi

    log_info "Requesting SSL certificate for ${DOMAIN}..."

    local ssl_success=false

    # Try using daemon first (webroot method)
    if [[ "$USE_DAEMON" == "true" ]]; then
        if daemon_ssl_request_letsencrypt "$DOMAIN" "$SSL_EMAIL" "${INSTALL_DIR}/public" false; then
            ssl_success=true
            log_success "SSL certificate obtained via daemon"
        else
            log_warning "Daemon SSL request failed, falling back to direct certbot"
        fi
    fi

    # Fallback to direct certbot (webroot method for consistency)
    if [[ "$ssl_success" != "true" ]]; then
        if certbot certonly --webroot \
            -w "${INSTALL_DIR}/public" \
            -d "$DOMAIN" \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" 2>&1; then
            ssl_success=true
            log_success "SSL certificate obtained via certbot"
        else
            log_warning "SSL certificate request failed. You can retry manually with:"
            log_warning "  certbot certonly --webroot -w ${INSTALL_DIR}/public -d ${DOMAIN}"
            return 1
        fi
    fi

    # Now update nginx configuration for SSL
    if [[ "$ssl_success" == "true" ]]; then
        configure_nginx_ssl
        setup_certbot_renewal
    fi
}

# =============================================================================
# Nginx SSL Configuration
# =============================================================================

configure_nginx_ssl() {
    log_info "Configuring Nginx for SSL..."

    local cert_path="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

    # Verify certificate files exist
    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        log_error "SSL certificate files not found at expected location"
        return 1
    fi

    # Generate SSL nginx configuration
    local ssl_config
    ssl_config=$(cat << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }

    # Allow ACME challenge for certificate renewal
    location /.well-known/acme-challenge/ {
        root ${INSTALL_DIR}/public;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${INSTALL_DIR}/public;

    # SSL Configuration
    ssl_certificate ${cert_path};
    ssl_certificate_key ${key_path};
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    index index.php;
    charset utf-8;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm-${LUMO_USER}.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
        fastcgi_connect_timeout 60;
        fastcgi_send_timeout 180;
        fastcgi_read_timeout 180;
    }

    # Block access to hidden files
    location ~ /\.(?!well-known).* {
        deny all;
    }

    # Block access to sensitive files
    location ~ /\.(env|git|svn) {
        deny all;
    }
}
EOF
)

    # Write the SSL configuration using daemon if available
    local nginx_conf_path="/etc/nginx/sites-available/lumo"

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_write_file "$nginx_conf_path" "$ssl_config" "root" "root" "0644" || {
            log_warning "Daemon failed to write nginx SSL config, using direct write"
            echo "$ssl_config" > "$nginx_conf_path"
        }
    else
        echo "$ssl_config" > "$nginx_conf_path"
    fi

    # Test and reload nginx
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
        log_success "Nginx SSL configuration applied"
    else
        log_error "Nginx SSL configuration test failed"
        return 1
    fi
}

# =============================================================================
# Certbot Renewal
# =============================================================================

setup_certbot_renewal() {
    log_info "Setting up automatic certificate renewal..."

    # Enable certbot timer for auto-renewal
    if systemctl list-unit-files | grep -q "certbot.timer"; then
        systemctl enable certbot.timer 2>/dev/null || true
        systemctl start certbot.timer 2>/dev/null || true
        log_success "Certbot auto-renewal enabled"
    else
        # Fallback: create cron job for renewal
        local cron_entry="0 0,12 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
        if ! grep -q "certbot renew" /etc/crontab 2>/dev/null; then
            echo "$cron_entry" >> /etc/crontab
            log_success "Certbot renewal cron job added"
        fi
    fi
}
