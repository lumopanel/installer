#!/usr/bin/env bash
#
# Common functions: logging, colors, helpers
#

# Prevent multiple inclusion
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
readonly _COMMON_SH_LOADED=1

# =============================================================================
# Colors (only set if terminal supports them)
# =============================================================================

if [[ -t 1 ]] && [[ -t 2 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m'
    readonly BOLD='\033[1m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
    readonly BOLD=''
fi

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "\n${CYAN}${BOLD}==> $1${NC}\n"
}

log_daemon() {
    echo -e "${YELLOW}[DAEMON]${NC} $1"
}

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $1"
}

# =============================================================================
# Error Handling
# =============================================================================

die() {
    log_error "$1"
    exit 1
}

# =============================================================================
# User Interaction
# =============================================================================

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    # Use /dev/tty if stdin is not a terminal (e.g., curl | bash)
    if [[ -t 0 ]]; then
        read -rp "$prompt" response
    else
        printf "%s" "$prompt"
        read -r response < /dev/tty
    fi
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local var_name="$3"
    local response

    if [[ -n "$default" ]]; then
        # Use /dev/tty if stdin is not a terminal (e.g., curl | bash)
        if [[ -t 0 ]]; then
            read -rp "$prompt [$default]: " response
        else
            printf "%s" "$prompt [$default]: "
            read -r response < /dev/tty
        fi
        response="${response:-$default}"
    else
        if [[ -t 0 ]]; then
            read -rp "$prompt: " response
        else
            printf "%s" "$prompt: "
            read -r response < /dev/tty
        fi
    fi

    printf -v "$var_name" '%s' "$response"
}

# =============================================================================
# Utility Functions
# =============================================================================

generate_password() {
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
}

command_exists() {
    command -v "$1" &>/dev/null
}

file_contains() {
    local file="$1"
    local pattern="$2"
    grep -q "$pattern" "$file" 2>/dev/null
}

wait_for_service() {
    local check_cmd="$1"
    local max_attempts="${2:-30}"
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if eval "$check_cmd" &>/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    return 1
}

# =============================================================================
# Cleanup Handler
# =============================================================================

declare -a CLEANUP_TASKS=()

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed! Performing cleanup..."

        # Iterate in reverse order (LIFO) for proper cleanup sequence
        local i
        for ((i=${#CLEANUP_TASKS[@]}-1; i>=0; i--)); do
            log_info "Cleanup: ${CLEANUP_TASKS[$i]}"
            eval "${CLEANUP_TASKS[$i]}" 2>/dev/null || true
        done
    fi

    exit $exit_code
}

add_cleanup_task() {
    CLEANUP_TASKS+=("$1")
}

clear_cleanup_tasks() {
    CLEANUP_TASKS=()
}

# Set up trap
trap cleanup EXIT
