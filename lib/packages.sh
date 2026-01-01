#!/usr/bin/env bash
#
# Package installation functions
#

[[ -n "${_PACKAGES_SH_LOADED:-}" ]] && return 0
readonly _PACKAGES_SH_LOADED=1

# =============================================================================
# Generic Package Installation
# =============================================================================

install_package() {
    local package="$1"

    if [[ "$USE_DAEMON" == "true" ]]; then
        if daemon_install_package "$package"; then
            return 0
        fi
        log_warning "Daemon failed to install $package, falling back to apt"
    fi

    apt-get install -y "$package"
}

# =============================================================================
# Bootstrap Packages
# =============================================================================

install_bootstrap_packages() {
    log_step "Installing bootstrap packages"

    apt-get update -qq

    apt-get install -y "${BOOTSTRAP_PACKAGES[@]}"

    log_success "Bootstrap packages installed"
}

# =============================================================================
# Redis
# =============================================================================

install_redis() {
    log_step "Installing Redis"

    install_package "redis-server"

    # Configure Redis for systemd supervision
    if [[ -f /etc/redis/redis.conf ]]; then
        sed -i 's/^supervised no$/supervised systemd/' /etc/redis/redis.conf 2>/dev/null || true
    fi

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_enable "redis-server" || systemctl enable redis-server
        daemon_service_restart "redis-server" || systemctl restart redis-server
    else
        systemctl enable redis-server
        systemctl restart redis-server
    fi

    if wait_for_service "redis-cli ping" 30; then
        log_success "Redis installed and responding"
    else
        log_warning "Redis may not be fully ready yet"
    fi
}

# =============================================================================
# Nginx
# =============================================================================

install_nginx() {
    log_step "Installing Nginx"

    install_package "nginx"

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_enable "nginx" || systemctl enable nginx
        daemon_service_start "nginx" || systemctl start nginx
    else
        systemctl enable nginx
        systemctl start nginx
    fi

    add_cleanup_task "systemctl stop nginx 2>/dev/null || true"

    log_success "Nginx installed"
}

# =============================================================================
# PHP
# =============================================================================

install_php() {
    log_step "Installing PHP ${PHP_VERSION}"

    # Add the Ondrej PPA for PHP
    if [[ ! -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list ]] && \
       [[ ! -f /etc/apt/sources.list.d/ondrej-*.list ]]; then
        log_info "Adding PHP repository..."
        if [[ "$USE_DAEMON" == "true" ]]; then
            daemon_exec "package.add_repository" '{"repository": "ppa:ondrej/php"}' "Adding Ondrej PHP PPA" || \
                add-apt-repository -y ppa:ondrej/php
        else
            add-apt-repository -y ppa:ondrej/php
        fi
        apt-get update -qq
    fi

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_exec "package.update" '{}' "Updating package lists" || apt-get update -qq

        daemon_install_php "$PHP_VERSION" || {
            log_warning "Daemon PHP install failed, using apt"
            apt-get install -y "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli"
        }

        for ext in "${PHP_EXTENSIONS[@]}"; do
            daemon_install_php_extension "$PHP_VERSION" "$ext" || \
                apt-get install -y "php${PHP_VERSION}-${ext}" 2>/dev/null || true
        done

        daemon_service_enable "php${PHP_VERSION}-fpm" || systemctl enable "php${PHP_VERSION}-fpm"
        daemon_service_start "php${PHP_VERSION}-fpm" || systemctl start "php${PHP_VERSION}-fpm"
    else
        apt-get install -y \
            "php${PHP_VERSION}" \
            "php${PHP_VERSION}-fpm" \
            "php${PHP_VERSION}-cli" \
            "php${PHP_VERSION}-common"

        for ext in "${PHP_EXTENSIONS[@]}"; do
            apt-get install -y "php${PHP_VERSION}-${ext}" 2>/dev/null || \
                log_warning "Could not install PHP extension: $ext"
        done

        systemctl enable "php${PHP_VERSION}-fpm"
        systemctl start "php${PHP_VERSION}-fpm"
    fi

    log_success "PHP ${PHP_VERSION} installed"
}

# =============================================================================
# MySQL
# =============================================================================

install_mysql() {
    log_step "Installing MySQL"

    install_package "mysql-server"

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_enable "mysql" || systemctl enable mysql
        daemon_service_start "mysql" || systemctl start mysql
    else
        systemctl enable mysql
        systemctl start mysql
    fi

    if wait_for_service "mysqladmin ping" 30; then
        log_success "MySQL installed and responding"
    else
        log_warning "MySQL may not be fully ready yet"
    fi
}

# =============================================================================
# PostgreSQL
# =============================================================================

install_postgresql() {
    log_step "Installing PostgreSQL"

    install_package "postgresql"
    install_package "postgresql-contrib"

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_service_enable "postgresql" || systemctl enable postgresql
        daemon_service_start "postgresql" || systemctl start postgresql
    else
        systemctl enable postgresql
        systemctl start postgresql
    fi

    if wait_for_service "sudo -u postgres pg_isready" 30; then
        log_success "PostgreSQL installed and responding"
    else
        log_warning "PostgreSQL may not be fully ready yet"
    fi
}

# =============================================================================
# Certbot
# =============================================================================

install_certbot() {
    log_step "Installing Certbot"

    install_package "certbot"
    install_package "python3-certbot-nginx"

    log_success "Certbot installed"
}

# =============================================================================
# Node.js
# =============================================================================

install_nodejs() {
    log_step "Installing Node.js"

    if ! command_exists node; then
        log_info "Adding Node.js repository..."
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    fi

    install_package "nodejs"

    log_success "Node.js installed: $(node --version 2>/dev/null || echo 'unknown')"
}

# =============================================================================
# Composer
# =============================================================================

install_composer() {
    log_step "Installing Composer"

    if command_exists composer; then
        log_info "Composer already installed, updating..."
        composer self-update 2>/dev/null || true
    else
        local expected_signature
        expected_signature=$(curl -sS https://composer.github.io/installer.sig)

        curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php

        local actual_signature
        actual_signature=$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")

        if [[ "$expected_signature" != "$actual_signature" ]]; then
            rm -f /tmp/composer-setup.php
            die "Composer installer signature mismatch!"
        fi

        php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
        rm -f /tmp/composer-setup.php
    fi

    log_success "Composer installed: $(composer --version 2>/dev/null | head -1 || echo 'unknown')"
}
