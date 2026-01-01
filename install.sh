#!/usr/bin/env bash
#
# Lumo Server Management Panel - Installation Script
#
# This script installs and configures both the Lumo panel and daemon
# on Ubuntu 22.04/24.04 systems.
#
# Usage: sudo bash install.sh
#

set -euo pipefail

# =============================================================================
# Script Setup
# =============================================================================

# Get the directory where the installer is located
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_DIR

# =============================================================================
# Load Configuration and Libraries
# =============================================================================

# Load default configuration
# shellcheck source=config/defaults.conf
source "${INSTALLER_DIR}/config/defaults.conf"

# Load libraries (order matters for dependencies)
# shellcheck source=lib/common.sh
source "${INSTALLER_DIR}/lib/common.sh"
# shellcheck source=lib/validation.sh
source "${INSTALLER_DIR}/lib/validation.sh"
# shellcheck source=lib/user.sh
source "${INSTALLER_DIR}/lib/user.sh"
# shellcheck source=lib/templates.sh
source "${INSTALLER_DIR}/lib/templates.sh"
# shellcheck source=lib/daemon.sh
source "${INSTALLER_DIR}/lib/daemon.sh"
# shellcheck source=lib/daemon-setup.sh
source "${INSTALLER_DIR}/lib/daemon-setup.sh"
# shellcheck source=lib/packages.sh
source "${INSTALLER_DIR}/lib/packages.sh"
# shellcheck source=lib/nginx.sh
source "${INSTALLER_DIR}/lib/nginx.sh"
# shellcheck source=lib/ssl.sh
source "${INSTALLER_DIR}/lib/ssl.sh"
# shellcheck source=lib/panel.sh
source "${INSTALLER_DIR}/lib/panel.sh"
# shellcheck source=lib/services.sh
source "${INSTALLER_DIR}/lib/services.sh"

# =============================================================================
# Installation State
# =============================================================================

OS_VERSION=""
DOMAIN=""
SSL_EMAIL=""
SKIP_SSL="false"
DB_CONNECTION=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

# =============================================================================
# User Input Collection
# =============================================================================

collect_information() {
    echo
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo -e "${CYAN}${BOLD}    Lumo Server Panel - Installation${NC}"
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo
    echo "This script will install and configure Lumo on your server."
    echo "Please provide the following information:"
    echo

    # Domain
    while true; do
        prompt_input "Enter your domain name (e.g., panel.example.com)" "" DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_error "Domain name is required"
        elif validate_domain "$DOMAIN"; then
            break
        else
            log_error "Invalid domain format. Please enter a valid domain."
        fi
    done

    # SSL Email
    while true; do
        prompt_input "Enter email for SSL certificate" "admin@${DOMAIN}" SSL_EMAIL
        if validate_email "$SSL_EMAIL"; then
            break
        else
            log_error "Invalid email format. Please enter a valid email."
        fi
    done

    # Skip SSL option
    if confirm "Set up SSL with Let's Encrypt?" "y"; then
        SKIP_SSL="false"
    else
        SKIP_SSL="true"
    fi

    # Database selection
    echo
    echo "Select database type:"
    echo "  1) MySQL (recommended for production)"
    echo "  2) PostgreSQL"
    echo "  3) SQLite (development only)"
    echo

    local db_choice
    read -rp "Choice [1]: " db_choice
    db_choice="${db_choice:-1}"

    case "$db_choice" in
        1)
            DB_CONNECTION="mysql"
            prompt_input "Database name" "lumo" DB_NAME
            prompt_input "Database user" "lumo" DB_USER
            DB_PASSWORD=$(generate_password)
            log_info "Generated secure database password"
            ;;
        2)
            DB_CONNECTION="pgsql"
            prompt_input "Database name" "lumo" DB_NAME
            prompt_input "Database user" "lumo" DB_USER
            DB_PASSWORD=$(generate_password)
            log_info "Generated secure database password"
            ;;
        3)
            DB_CONNECTION="sqlite"
            DB_NAME=""
            DB_USER=""
            DB_PASSWORD=""
            log_warning "SQLite is not recommended for production use"
            ;;
        *)
            log_error "Invalid choice, defaulting to MySQL"
            DB_CONNECTION="mysql"
            DB_NAME="lumo"
            DB_USER="lumo"
            DB_PASSWORD=$(generate_password)
            ;;
    esac

    echo
    echo -e "${BOLD}Installation Summary:${NC}"
    echo -e "  Domain: ${DOMAIN}"
    echo -e "  SSL Email: ${SSL_EMAIL}"
    echo -e "  SSL: $([ "$SKIP_SSL" == "true" ] && echo "Skipped" || echo "Let's Encrypt")"
    echo -e "  Database: ${DB_CONNECTION}"
    if [[ -n "$DB_NAME" ]]; then
        echo -e "  DB Name: ${DB_NAME}"
        echo -e "  DB User: ${DB_USER}"
    fi
    echo

    if ! confirm "Proceed with installation?" "y"; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# =============================================================================
# Summary Output
# =============================================================================

print_summary() {
    local protocol="https"
    [[ "$SKIP_SSL" == "true" ]] && protocol="http"

    echo
    echo -e "${GREEN}${BOLD}=============================================${NC}"
    echo -e "${GREEN}${BOLD}    Lumo Installation Complete!${NC}"
    echo -e "${GREEN}${BOLD}=============================================${NC}"
    echo
    echo -e "${BOLD}Panel URL:${NC} ${protocol}://${DOMAIN}"
    echo -e "${BOLD}Horizon Dashboard:${NC} ${protocol}://${DOMAIN}/horizon"
    echo
    echo -e "${BOLD}Installation Directory:${NC} ${INSTALL_DIR}"
    echo -e "${BOLD}Daemon Config:${NC} ${DAEMON_CONFIG_DIR}/daemon.toml"
    echo
    echo -e "${BOLD}Database:${NC}"
    case "$DB_CONNECTION" in
        mysql)
            echo -e "  Type: MySQL"
            echo -e "  Database: ${DB_NAME}"
            echo -e "  User: ${DB_USER}"
            ;;
        pgsql)
            echo -e "  Type: PostgreSQL"
            echo -e "  Database: ${DB_NAME}"
            echo -e "  User: ${DB_USER}"
            ;;
        sqlite)
            echo -e "  Type: SQLite"
            echo -e "  Path: ${INSTALL_DIR}/database/database.sqlite"
            ;;
    esac
    echo
    echo -e "${BOLD}User:${NC}"
    echo -e "  System user: ${LUMO_USER} (UID: ${LUMO_UID})"
    echo -e "  Home directory: ${LUMO_HOME}"
    echo
    echo -e "${BOLD}Services:${NC}"
    echo -e "  lumo-daemon  - Privilege daemon (authenticates ${LUMO_USER})"
    echo -e "  lumo-horizon - Queue worker (runs as ${LUMO_USER})"
    echo -e "  php${PHP_VERSION}-fpm - PHP-FPM with dedicated ${LUMO_USER} pool"
    echo
    echo -e "${BOLD}Useful Commands:${NC}"
    echo -e "  systemctl status lumo-daemon    # Check daemon status"
    echo -e "  systemctl status lumo-horizon   # Check Horizon status"
    echo -e "  sudo -u ${LUMO_USER} php artisan tinker  # Laravel REPL"
    echo -e "  tail -f ${INSTALL_DIR}/storage/logs/laravel.log  # View logs"
    echo

    if [[ "$SKIP_SSL" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}Note:${NC} SSL was skipped. Run this to enable:"
        echo -e "  certbot --nginx -d ${DOMAIN}"
        echo
    fi

    echo -e "${BOLD}Next Steps:${NC}"
    echo -e "  1. Visit ${protocol}://${DOMAIN} to complete setup"
    echo -e "  2. Create your admin account"
    echo -e "  3. Configure your servers"
    echo

    # Save credentials to file
    local creds_file="${INSTALL_DIR}/INSTALL_CREDENTIALS.txt"
    cat > "$creds_file" << EOF
Lumo Installation Credentials
Generated: $(date)
=============================

Domain: ${DOMAIN}
Installation Directory: ${INSTALL_DIR}

System User:
  Username: ${LUMO_USER}
  UID: ${LUMO_UID}
  Home: ${LUMO_HOME}

Database:
  Type: ${DB_CONNECTION}
  Name: ${DB_NAME:-SQLite}
  User: ${DB_USER:-N/A}
  Password: ${DB_PASSWORD:-N/A}

Daemon:
  Socket: ${DAEMON_SOCKET_PATH}
  Secret (base64): ${DAEMON_SECRET}
  Allowed UIDs: 0, ${LUMO_UID}

Server ID:
$(grep LOCAL_SERVER_ID "${INSTALL_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "N/A")

IMPORTANT: Delete this file after noting these credentials!
EOF
    chmod 600 "$creds_file"
    chown root:root "$creds_file"

    echo -e "${YELLOW}${BOLD}Credentials saved to:${NC} ${creds_file}"
    echo -e "${RED}${BOLD}DELETE THIS FILE after noting the credentials!${NC}"
    echo
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Run pre-flight checks
    run_preflight_checks

    # Collect configuration
    collect_information

    # Phase 1: Bootstrap
    log_step "Phase 1: Bootstrap"
    install_bootstrap_packages

    # Phase 2: Daemon Installation
    log_step "Phase 2: Daemon Installation"
    install_daemon
    configure_daemon
    create_daemon_service
    init_daemon_communication || true

    # Phase 3: Core Services
    log_step "Phase 3: Core Services"
    install_redis
    install_nginx
    install_php
    configure_php_fpm_pool
    install_certbot
    install_nodejs

    # Install database
    case "$DB_CONNECTION" in
        mysql) install_mysql ;;
        pgsql) install_postgresql ;;
    esac

    install_composer

    # Phase 4: Panel Installation
    log_step "Phase 4: Panel Installation"
    install_panel
    setup_database
    install_panel_dependencies
    configure_panel
    run_migrations
    optimize_panel

    # Phase 5: Web Server & Services
    log_step "Phase 5: Web Server & Services"
    configure_nginx
    setup_ssl
    create_horizon_service
    setup_scheduler
    start_services

    # Clear cleanup tasks on success
    clear_cleanup_tasks

    # Print summary
    print_summary
}

# Run main function
main "$@"
