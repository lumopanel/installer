#!/usr/bin/env bash
#
# Daemon client functions for communicating with the Lumo daemon
#

[[ -n "${_DAEMON_SH_LOADED:-}" ]] && return 0
readonly _DAEMON_SH_LOADED=1

# Global state
HMAC_SECRET=""
HMAC_SECRET_PATH=""
DAEMON_SECRET=""
USE_DAEMON=true

# =============================================================================
# HMAC Signature Generation
# =============================================================================

# Generate HMAC-SHA256 signature for daemon requests
# Per documentation: signature is hex-encoded HMAC-SHA256
# Signing message format: {command}:{params_json}:{timestamp}:{nonce}
generate_hmac_signature() {
    local command="$1"
    local params_json="$2"
    local timestamp="$3"
    local nonce="$4"

    local signing_message="${command}:${params_json}:${timestamp}:${nonce}"
    echo -n "$signing_message" | openssl dgst -sha256 -hmac "$HMAC_SECRET" | awk '{print $2}'
}

# =============================================================================
# Daemon Communication
# =============================================================================

# Send a command to the daemon and get response
daemon_call() {
    local command="$1"
    local params="$2"

    local timestamp
    timestamp=$(date +%s)
    local nonce
    # Use uuidgen if available (more portable), fallback to /proc
    if command -v uuidgen &>/dev/null; then
        nonce=$(uuidgen)
    else
        nonce=$(cat /proc/sys/kernel/random/uuid)
    fi

    # Get compact JSON for signing
    local params_compact
    params_compact=$(echo "$params" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), separators=(',', ':')))")

    local signature
    signature=$(generate_hmac_signature "$command" "$params_compact" "$timestamp" "$nonce")

    python3 << PYTHON_EOF
import socket
import json
import struct
import sys

sock_path = "${DAEMON_SOCKET_PATH}"
request = {
    "command": "${command}",
    "params": ${params},
    "timestamp": ${timestamp},
    "nonce": "${nonce}",
    "signature": "${signature}"
}

try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(300)
    sock.connect(sock_path)

    json_bytes = json.dumps(request).encode('utf-8')
    sock.sendall(struct.pack('>I', len(json_bytes)))
    sock.sendall(json_bytes)

    len_buf = sock.recv(4)
    if len(len_buf) < 4:
        print(json.dumps({"success": False, "error": "Connection closed unexpectedly"}))
        sys.exit(1)

    resp_len = struct.unpack('>I', len_buf)[0]
    if resp_len > 10485760:
        print(json.dumps({"success": False, "error": "Response too large"}))
        sys.exit(1)

    response_buf = b''
    while len(response_buf) < resp_len:
        chunk = sock.recv(min(4096, resp_len - len(response_buf)))
        if not chunk:
            break
        response_buf += chunk

    sock.close()
    response = json.loads(response_buf.decode('utf-8'))
    print(json.dumps(response))

except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
    sys.exit(1)
PYTHON_EOF
}

# Execute daemon command with logging and error handling
daemon_exec() {
    local command="$1"
    local params="$2"
    local description="$3"

    log_daemon "Executing: ${description}"

    local response
    if ! response=$(daemon_call "$command" "$params" 2>&1); then
        log_error "$description - daemon call failed"
        return 1
    fi

    local success
    success=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print('True' if d.get('success') else 'False')" 2>/dev/null) || success="False"

    if [[ "$success" == "True" ]]; then
        log_success "$description - completed"
        return 0
    else
        local error
        error=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error', {}).get('message', 'Unknown error') if isinstance(d.get('error'), dict) else d.get('error', 'Unknown error'))" 2>/dev/null) || error="Unknown error"
        log_error "$description - failed: $error"
        return 1
    fi
}

# =============================================================================
# Daemon Command Wrappers
# =============================================================================

daemon_install_package() {
    local package="$1"
    daemon_exec "package.install" "{\"packages\": [\"${package}\"]}" "Installing package: ${package}"
}

daemon_install_php() {
    local version="$1"
    daemon_exec "php.install_version" "{\"version\": \"${version}\"}" "Installing PHP ${version}"
}

daemon_install_php_extension() {
    local version="$1"
    local extension="$2"
    daemon_exec "php.install_extension" "{\"version\": \"${version}\", \"extension\": \"${extension}\"}" "Installing PHP ${version} extension: ${extension}"
}

daemon_service_start() {
    local service="$1"
    daemon_exec "service.start" "{\"service\": \"${service}\"}" "Starting service: ${service}"
}

daemon_service_stop() {
    local service="$1"
    daemon_exec "service.stop" "{\"service\": \"${service}\"}" "Stopping service: ${service}"
}

daemon_service_enable() {
    local service="$1"
    daemon_exec "service.enable" "{\"service\": \"${service}\"}" "Enabling service: ${service}"
}

daemon_service_restart() {
    local service="$1"
    daemon_exec "service.restart" "{\"service\": \"${service}\"}" "Restarting service: ${service}"
}

daemon_service_reload() {
    local service="$1"
    daemon_exec "service.reload" "{\"service\": \"${service}\"}" "Reloading service: ${service}"
}

daemon_write_file() {
    local path="$1"
    local content="$2"
    local owner="${3:-root}"
    local group="${4:-root}"
    local mode="${5:-0644}"

    local escaped_content
    escaped_content=$(printf '%s' "$content" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

    daemon_exec "file.write" "{\"path\": \"${path}\", \"content\": ${escaped_content}, \"owner\": \"${owner}\", \"group\": \"${group}\", \"mode\": \"${mode}\"}" "Writing file: ${path}"
}

daemon_mkdir() {
    local path="$1"
    local owner="${2:-root}"
    local group="${3:-root}"
    local mode="${4:-0755}"

    daemon_exec "file.mkdir" "{\"path\": \"${path}\", \"owner\": \"${owner}\", \"group\": \"${group}\", \"mode\": \"${mode}\"}" "Creating directory: ${path}"
}

daemon_nginx_enable_site() {
    local site="$1"
    daemon_exec "nginx.enable_site" "{\"site\": \"${site}\"}" "Enabling nginx site: ${site}"
}

daemon_nginx_test_config() {
    daemon_exec "nginx.test_config" "{}" "Testing nginx configuration"
}

daemon_nginx_disable_site() {
    local site="$1"
    daemon_exec "nginx.disable_site" "{\"site_name\": \"${site}\"}" "Disabling nginx site: ${site}"
}

# =============================================================================
# SSL/TLS Wrappers
# =============================================================================

daemon_ssl_request_letsencrypt() {
    local domain="$1"
    local email="$2"
    local webroot="$3"
    local staging="${4:-false}"

    daemon_exec "ssl.request_letsencrypt" \
        "{\"domain\": \"${domain}\", \"email\": \"${email}\", \"webroot\": \"${webroot}\", \"staging\": ${staging}}" \
        "Requesting Let's Encrypt certificate for ${domain}"
}

daemon_ssl_install_cert() {
    local domain="$1"
    local cert_path="$2"
    local key_path="$3"
    local chain_path="${4:-}"

    local params="{\"domain\": \"${domain}\", \"certificate\": \"${cert_path}\", \"private_key\": \"${key_path}\""
    if [[ -n "$chain_path" ]]; then
        params="${params}, \"chain\": \"${chain_path}\"}"
    else
        params="${params}}"
    fi

    daemon_exec "ssl.install_cert" "$params" "Installing SSL certificate for ${domain}"
}

# =============================================================================
# Database Wrappers
# =============================================================================

daemon_create_database() {
    local name="$1"
    local type="$2"  # mysql or pgsql

    daemon_exec "database.create_db" \
        "{\"name\": \"${name}\", \"type\": \"${type}\"}" \
        "Creating ${type} database: ${name}"
}

daemon_create_db_user() {
    local username="$1"
    local password="$2"
    local database="$3"
    local type="$4"  # mysql or pgsql

    # Escape password for JSON
    local escaped_password
    escaped_password=$(printf '%s' "$password" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

    daemon_exec "database.create_user" \
        "{\"username\": \"${username}\", \"password\": ${escaped_password}, \"database\": \"${database}\", \"type\": \"${type}\"}" \
        "Creating ${type} database user: ${username}"
}

daemon_grant_db_privileges() {
    local username="$1"
    local database="$2"
    local type="$3"  # mysql or pgsql

    daemon_exec "database.grant_privileges" \
        "{\"username\": \"${username}\", \"database\": \"${database}\", \"type\": \"${type}\"}" \
        "Granting privileges on ${database} to ${username}"
}

# =============================================================================
# File Operations Wrappers
# =============================================================================

daemon_file_delete() {
    local path="$1"
    daemon_exec "file.delete" "{\"path\": \"${path}\"}" "Deleting file: ${path}"
}

daemon_file_chmod() {
    local path="$1"
    local mode="$2"
    local recursive="${3:-false}"

    daemon_exec "file.chmod" \
        "{\"path\": \"${path}\", \"mode\": \"${mode}\", \"recursive\": ${recursive}}" \
        "Setting permissions on: ${path}"
}

# =============================================================================
# Daemon Status
# =============================================================================

daemon_ping() {
    local response
    response=$(daemon_call "system.ping" "{}" 2>/dev/null) || return 1

    local success
    success=$(echo "$response" | python3 -c "import sys,json; print('True' if json.load(sys.stdin).get('success') else 'False')" 2>/dev/null) || return 1

    [[ "$success" == "True" ]]
}

wait_for_daemon() {
    local max_attempts=30
    local attempt=0
    local wait_time=1

    log_info "Waiting for daemon to be ready..."

    while [[ $attempt -lt $max_attempts ]]; do
        if daemon_ping; then
            log_success "Daemon is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep $wait_time

        if [[ $wait_time -lt 5 ]]; then
            wait_time=$((wait_time + 1))
        fi
    done

    log_error "Daemon failed to respond after ${max_attempts} attempts"
    return 1
}

init_daemon_communication() {
    log_step "Initializing daemon communication"

    if ! wait_for_daemon; then
        log_warning "Daemon communication failed. Falling back to direct installation."
        USE_DAEMON=false
        return 1
    fi

    log_success "Daemon communication established"
    return 0
}
