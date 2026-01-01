#!/usr/bin/env bash
#
# Template rendering functions
#

[[ -n "${_TEMPLATES_SH_LOADED:-}" ]] && return 0
readonly _TEMPLATES_SH_LOADED=1

# Get the installer's base directory
get_installer_dir() {
    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

    # If we're in lib/, go up one level
    if [[ "$(basename "$script_path")" == "lib" ]]; then
        dirname "$script_path"
    else
        echo "$script_path"
    fi
}

INSTALLER_DIR="${INSTALLER_DIR:-$(get_installer_dir)}"
TEMPLATES_DIR="${INSTALLER_DIR}/config/templates"

# Render a template file, replacing {{VAR}} placeholders with shell variables
render_template() {
    local template_file="$1"
    local content

    if [[ ! -f "$template_file" ]]; then
        log_error "Template not found: $template_file"
        return 1
    fi

    content=$(cat "$template_file")

    # Replace all {{VAR}} patterns with the value of $VAR
    while [[ "$content" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        content="${content//\{\{${var_name}\}\}/${var_value}}"
    done

    echo "$content"
}

# Render a template and write to a file
render_template_to_file() {
    local template_name="$1"
    local output_path="$2"
    local owner="${3:-root}"
    local group="${4:-root}"
    local mode="${5:-0644}"

    local template_file="${TEMPLATES_DIR}/${template_name}"
    local content

    if ! content=$(render_template "$template_file"); then
        return 1
    fi

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_write_file "$output_path" "$content" "$owner" "$group" "$mode" || {
            log_warning "Daemon failed to write $output_path, falling back to direct write"
            echo "$content" > "$output_path"
            chown "${owner}:${group}" "$output_path"
            chmod "$mode" "$output_path"
        }
    else
        echo "$content" > "$output_path"
        chown "${owner}:${group}" "$output_path"
        chmod "$mode" "$output_path"
    fi
}

# Copy a static template file (no rendering)
copy_template() {
    local template_name="$1"
    local output_path="$2"
    local owner="${3:-root}"
    local group="${4:-root}"
    local mode="${5:-0644}"

    local template_file="${TEMPLATES_DIR}/${template_name}"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template not found: $template_file"
        return 1
    fi

    local content
    content=$(cat "$template_file")

    if [[ "$USE_DAEMON" == "true" ]]; then
        daemon_write_file "$output_path" "$content" "$owner" "$group" "$mode" || {
            log_warning "Daemon failed to write $output_path, falling back to direct write"
            cp "$template_file" "$output_path"
            chown "${owner}:${group}" "$output_path"
            chmod "$mode" "$output_path"
        }
    else
        cp "$template_file" "$output_path"
        chown "${owner}:${group}" "$output_path"
        chmod "$mode" "$output_path"
    fi
}
