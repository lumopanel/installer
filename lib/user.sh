#!/usr/bin/env bash
#
# User management functions
#

[[ -n "${_USER_SH_LOADED:-}" ]] && return 0
readonly _USER_SH_LOADED=1

# =============================================================================
# User Management
# =============================================================================

ensure_lumo_user() {
    log_info "Ensuring ${LUMO_USER} user exists..."

    if ! id "$LUMO_USER" &>/dev/null; then
        log_info "Creating ${LUMO_USER} user..."

        # Create the lumo group
        groupadd -r "$LUMO_GROUP" 2>/dev/null || true

        # Create the lumo user with a proper home directory
        useradd -r -g "$LUMO_GROUP" -d "$LUMO_HOME" -m -s /bin/bash "$LUMO_USER" 2>/dev/null || true

        # Add lumo user to www-data group for nginx socket access (if www-data exists)
        if getent group www-data &>/dev/null; then
            usermod -aG www-data "$LUMO_USER" 2>/dev/null || true
        fi
    fi

    # Ensure home directory exists with correct permissions
    mkdir -p "$LUMO_HOME"
    chown "$LUMO_USER:$LUMO_GROUP" "$LUMO_HOME"
    chmod 750 "$LUMO_HOME"

    LUMO_UID=$(id -u "$LUMO_USER")
    LUMO_GID=$(id -g "$LUMO_USER")

    log_success "${LUMO_USER} user ready (UID: $LUMO_UID, GID: $LUMO_GID)"
}

add_user_to_group() {
    local user="$1"
    local group="$2"

    if getent group "$group" &>/dev/null; then
        usermod -aG "$group" "$user" 2>/dev/null || true
        log_info "Added $user to $group group"
    fi
}
