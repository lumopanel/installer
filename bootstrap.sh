#!/usr/bin/env bash
#
# Lumo Server Management Panel - Bootstrap Script
#
# This script downloads and runs the Lumo installer without requiring git.
# It can be run directly via curl or wget:
#
#   curl -sSL https://raw.githubusercontent.com/lumopanel/installer/main/bootstrap.sh | sudo bash
#   wget -qO- https://raw.githubusercontent.com/lumopanel/installer/main/bootstrap.sh | sudo bash
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

REPO_URL="${LUMO_INSTALLER_REPO:-https://raw.githubusercontent.com/lumopanel/installer/main}"
INSTALL_TMP="${LUMO_INSTALLER_TMP:-/tmp/lumo-installer}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Detect available download tool
detect_downloader() {
    if command -v curl &>/dev/null; then
        echo "curl"
    elif command -v wget &>/dev/null; then
        echo "wget"
    else
        echo ""
    fi
}

# Download a file using available tool
download_file() {
    local url="$1"
    local output="$2"
    local downloader

    downloader=$(detect_downloader)

    case "$downloader" in
        curl)
            curl -sSfL "$url" -o "$output" 2>/dev/null
            ;;
        wget)
            wget -q "$url" -O "$output" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_requirements() {
    local errors=0

    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        errors=$((errors + 1))
    fi

    # Check download tool
    if [[ -z $(detect_downloader) ]]; then
        log_error "Neither curl nor wget found. Please install one:"
        log_error "  apt install curl   OR   apt install wget"
        errors=$((errors + 1))
    fi

    # Check OS
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_warning "This installer is designed for Ubuntu. Detected: $ID"
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        exit 1
    fi
}

# =============================================================================
# File Download
# =============================================================================

# Files to download (relative paths)
declare -a FILES=(
    "install.sh"
    "config/defaults.conf"
    "config/templates/daemon.toml"
    "config/templates/lumo-daemon.service"
    "config/templates/lumo-horizon.service"
    "config/templates/nginx-site.conf"
    "config/templates/php-fpm-pool.conf"
    "lib/common.sh"
    "lib/daemon-setup.sh"
    "lib/daemon.sh"
    "lib/nginx.sh"
    "lib/packages.sh"
    "lib/panel.sh"
    "lib/services.sh"
    "lib/ssl.sh"
    "lib/templates.sh"
    "lib/user.sh"
    "lib/validation.sh"
)

download_installer() {
    log_info "Preparing installation directory..."

    # Clean up any previous attempt
    rm -rf "$INSTALL_TMP"

    # Create directory structure
    mkdir -p "$INSTALL_TMP"/{config/templates,lib}

    log_info "Downloading installer files..."

    local failed=0
    local total=${#FILES[@]}
    local current=0

    for file in "${FILES[@]}"; do
        current=$((current + 1))
        local url="${REPO_URL}/${file}"
        local output="${INSTALL_TMP}/${file}"

        # Show progress
        printf "\r  Downloading: [%d/%d] %s" "$current" "$total" "$file"

        if ! download_file "$url" "$output"; then
            echo
            log_error "Failed to download: $file"
            failed=$((failed + 1))
            continue
        fi
    done

    echo  # New line after progress

    if [[ $failed -gt 0 ]]; then
        log_error "Failed to download $failed file(s)"
        log_error "Check your internet connection and try again"
        rm -rf "$INSTALL_TMP"
        exit 1
    fi

    # Make install script executable
    chmod +x "${INSTALL_TMP}/install.sh"

    log_success "Downloaded $total files successfully"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo -e "${CYAN}${BOLD}    Lumo Server Panel - Bootstrap${NC}"
    echo -e "${CYAN}${BOLD}=============================================${NC}"
    echo

    # Run checks
    check_requirements

    # Download files
    download_installer

    # Run the main installer
    log_info "Starting installer..."
    echo

    cd "$INSTALL_TMP"

    # When run via curl|bash, stdin is consumed by curl.
    # Redirect stdin from /dev/tty to allow interactive prompts.
    if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
        exec bash install.sh "$@" < /dev/tty
    else
        exec bash install.sh "$@"
    fi
}

main "$@"
