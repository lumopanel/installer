#!/usr/bin/env bash
#
# Validation functions: pre-flight checks, input validation
#

[[ -n "${_VALIDATION_SH_LOADED:-}" ]] && return 0
readonly _VALIDATION_SH_LOADED=1

# =============================================================================
# Input Validation
# =============================================================================

validate_domain() {
    local domain="$1"

    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi

    # Must have at least one dot for a proper domain
    if [[ ! "$domain" =~ \. ]]; then
        return 1
    fi

    return 0
}

validate_email() {
    local email="$1"

    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi

    return 0
}

# =============================================================================
# System Checks
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS. This script requires Ubuntu 22.04 or 24.04"
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        die "This script requires Ubuntu. Detected: $ID"
    fi

    if [[ ! "$VERSION_ID" =~ ^(22\.04|24\.04)$ ]]; then
        log_warning "This script is tested on Ubuntu 22.04 and 24.04. Detected: $VERSION_ID"
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    fi

    OS_VERSION="$VERSION_ID"
    log_info "Detected Ubuntu $OS_VERSION"
}

check_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|aarch64)
            log_info "Architecture: $arch"
            ;;
        *)
            die "Unsupported architecture: $arch. Only x86_64 and aarch64 are supported."
            ;;
    esac
}

check_memory() {
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))

    if [[ $mem_mb -lt 1024 ]]; then
        log_warning "System has ${mem_mb}MB RAM. Minimum recommended is 1024MB."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_info "Memory: ${mem_mb}MB"
    fi
}

check_disk_space() {
    local available_kb
    available_kb=$(df /var | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))

    if [[ $available_gb -lt 5 ]]; then
        log_warning "Only ${available_gb}GB available in /var. Minimum recommended is 5GB."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_info "Available disk space: ${available_gb}GB"
    fi
}

check_ports() {
    local ports=("$@")

    for port in "${ports[@]}"; do
        if ss -tlnp | grep -q ":${port} "; then
            log_warning "Port $port is already in use"
            if ! confirm "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    done
}

check_internet() {
    if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        log_warning "Cannot reach github.com. Internet connectivity may be limited."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    fi
}

# =============================================================================
# Pre-flight Check Runner
# =============================================================================

run_preflight_checks() {
    log_step "Running pre-flight checks"

    check_root
    check_os
    check_architecture
    check_memory
    check_disk_space
    check_ports 80 443
    check_internet

    log_success "Pre-flight checks passed"
}
