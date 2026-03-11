#!/bin/bash
# Script: rise-update.sh
# Version: 1.0.0
# Description: RISE System Update Management - APT package updates

set -Eeuo pipefail

readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

export LANG=C
export LC_ALL=C

# flock on FD 200 - prevents concurrent operations
exec 200>/var/lock/rise-operation.lock
flock -n 200 || {
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg code "ERR_LOCKED" \
        --arg message "Another RISE operation in progress" \
        --arg exit_code "4" \
        '{status: "error", api_version: $api_version, code: $code, message: $message, exit_code: ($exit_code | tonumber)}'
    exit 4
}

TMPFILE=$(mktemp /tmp/rise-update-XXXXXX)

cleanup() {
    local exit_code=$?
    rm -f "$TMPFILE"
    flock -u 200 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT ERR INT TERM

die() {
    local code="$1"
    local message="$2"
    local exit_code="${3:-1}"

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg code "$code" \
        --arg message "$message" \
        --arg exit_code "$exit_code" \
        '{status: "error", api_version: $api_version, code: $code, message: $message, exit_code: ($exit_code | tonumber)}' >&2

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg code "$code" \
        --arg message "$message" \
        --arg exit_code "$exit_code" \
        '{status: "error", api_version: $api_version, code: $code, message: $message, exit_code: ($exit_code | tonumber)}'

    exit "$exit_code"
}

log_event() {
    logger -t "$(basename "$0")" -p user.info "$*"
}

# Validate package name (APT format)
validate_package_name() {
    local pkg_name="$1"
    
    # APT package names: lowercase alphanumeric, +, -, ., _
    if [[ ! "$pkg_name" =~ ^[a-z0-9][a-z0-9+.\-_]*$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid package name: $pkg_name\"}"
        return 1
    fi
    
    # Check length
    if [ ${#pkg_name} -gt 128 ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid package name: $pkg_name (too long)\"}"
        return 1
    fi
    
    return 0
}

# Validate repository URL
validate_repo_url() {
    local url="$1"
    
    # Basic URL validation
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid repository URL: $url\"}"
        return 1
    fi
    
    return 0
}

# Validate GPG key ID
validate_gpg_key_id() {
    local key_id="$1"
    
    # GPG key IDs are 8 or 16 hex characters, or full fingerprint
    if [[ ! "$key_id" =~ ^[0-9A-Fa-f]{8,16}$ ]] && \
       [[ ! "$key_id" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid GPG key ID: $key_id\"}"
        return 1
    fi
    
    return 0
}

# Validate version string
validate_version() {
    local version="$1"
    
    # Basic version validation (semver-like: major.minor.patch)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid version string: $version\"}"
        return 1
    fi
    
    return 0
}

# Validate file path
validate_path() {
    local path="$1"
    
    # Check for empty path
    if [ -z "$path" ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid path: empty path\"}"
        return 1
    fi
    
    # Check for path traversal attempts
    if [[ "$path" == *".."* ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid path: path traversal not allowed\"}"
        return 1
    fi
    
    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid path: null bytes not allowed\"}"
        return 1
    fi
    
    # Check for dangerous characters (basic check)
    if [[ "$path" =~ [\;\|\&\`\$\(\)] ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid path: dangerous characters detected\"}"
        return 1
    fi
    
    return 0
}

# APT lock check
check_apt_lock() {
    local lock_files=(
        /var/lib/dpkg/lock-frontend
        /var/lib/dpkg/lock
        /var/lib/apt/lists/lock
        /var/cache/apt/archives/lock
    )
    for f in "${lock_files[@]}"; do
        if [ -f "$f" ] && fuser "$f" >/dev/null 2>&1; then
            die ERR_LOCKED "APT locked by another process (file: $f)"
        fi
    done
}

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

# Feature: --upgrade-pkgs (upgrade specific packages)
upgrade_packages() {
    check_apt_lock
    
    # Get packages to upgrade from stdin or arguments
    local packages=()
    
    if [ -t 0 ]; then
        # No stdin, check arguments
        if [ $# -eq 0 ]; then
            die ERR_INVALID_ARGUMENTS "No packages specified"
        fi
        packages=("$@")
    else
        # Read from stdin (one package per line)
        while IFS= read -r pkg; do
            [ -n "$pkg" ] && packages+=("$pkg")
        done
    fi
    
    # Validate each package name
    for pkg in "${packages[@]}"; do
        local pkg_validation=$(validate_package_name "$pkg")
        if [ $? -ne 0 ]; then
            die ERR_INVALID_INPUT "$pkg_validation"
        fi
    done
    
    # Check if packages exist
    for pkg in "${packages[@]}"; do
        if ! apt-cache policy "$pkg" >/dev/null 2>&1; then
            die ERR_PACKAGE_NOT_FOUND "Package not found: $pkg"
        fi
    done

    # Actual upgrade with 180s timeout
    export DEBIAN_FRONTEND=noninteractive

    if ! timeout 180 apt-get install -y -qq "${packages[@]}" 2>&1; then
        die ERR_OPERATION_FAILED "Package upgrade failed"
    fi

    log_event "Packages upgraded: ${packages[*]}"

    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson packages "$(echo "${packages[@]}" | jq -R -s 'split(" ")')" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Packages upgraded successfully",
            packages: $packages
        }'
}

# Feature: --check
check_updates() {
    check_apt_lock

    # Refresh package index with timeout
    timeout 180 apt-get update >/dev/null 2>&1 \
        || die ERR_APT_UPDATE_FAILED "apt-get update failed or timed out (180s)"

    # Dry-run to see what would be upgraded
    local dry_output
    dry_output=$(LANG=C LC_ALL=C apt-get full-upgrade --dry-run 2>/dev/null)

    # Parse upgradeable packages
    local packages_json="[]"
    local security_count=0
    local total_count=0

    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        # Parse: Inst package [current] (new origin)
        local pkg_name=$(echo "$line" | awk '{print $2}')
        [ -z "$pkg_name" ] && continue

        local current=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
        local new=$(echo "$line" | sed -n 's/.*(\([^ ]*\).*/\1/p')
        local origin=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')

        local pkg_type="standard"
        if [[ "$origin" == *"Debian-Security"* ]] || [[ "$origin" == *"security"* ]]; then
            pkg_type="security"
            ((security_count++)) || true
        fi
        ((total_count++)) || true

        local pkg_obj=$(jq -n \
            --arg name "$pkg_name" \
            --arg current "$current" \
            --arg new "$new" \
            --arg type "$pkg_type" \
            '{name: $name, current: $current, new: $new, type: $type}')

        packages_json=$(echo "$packages_json" | jq --argjson obj "$pkg_obj" '. += [$obj]')
    done < <(echo "$dry_output" | grep "^Inst " || true)

    # Parse packages to be removed
    local removed_json="[]"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local pkg_name=$(echo "$line" | awk '{print $2}')
        [ -z "$pkg_name" ] && continue
        local bracket_count=$(echo "$line" | tr -cd '[' | wc -c)
        local reason="removed by full-upgrade"

        if [ "$bracket_count" -ge 2 ]; then
            reason=$(echo "$line" | sed -n 's/.*\]\s*\[\(.*\)\]/\1/p')
        fi

        local removed_obj=$(jq -n \
            --arg name "$pkg_name" \
            --arg reason "$reason" \
            '{name: $name, reason: $reason}')

        removed_json=$(echo "$removed_json" | jq --argjson obj "$removed_obj" '. += [$obj]')
    done < <(echo "$dry_output" | grep "^Remv " || true)

    # Parse held packages
    local held_json="[]"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local pkg_name=$(echo "$line" | awk '{print $1}')
        [ -z "$pkg_name" ] && continue
        local held_obj=$(jq -n \
            --arg name "$pkg_name" \
            --arg reason "held back" \
            '{name: $name, reason: $reason}')
        held_json=$(echo "$held_json" | jq --argjson obj "$held_obj" '. += [$obj]')
    done < <(apt-mark showhold 2>/dev/null || true)

    log_event "Update check: ${total_count} packages available (${security_count} security)"

    # Build response with clarification message
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson total "$total_count" \
        --argjson security "$security_count" \
        --argjson packages "$packages_json" \
        --argjson removed "$removed_json" \
        --argjson held "$held_json" \
        '{
            status: "success",
            api_version: $api_version,
            message: (if $total > 0 then
                "Updates available. This operation will install/upgrade packages."
            else
                "System is up to date."
            end),
            data: {
                summary: {total: $total, security: $security},
                packages: $packages,
                removed: $removed,
                held: $held
            }
        }'
}

# Feature: --upgrade
upgrade_system() {
    check_apt_lock

    # Actual upgrade with 180s timeout
    export DEBIAN_FRONTEND=noninteractive

    if ! timeout 180 apt-get full-upgrade -y -qq 2>&1; then
        die ERR_OPERATION_FAILED "apt-get full-upgrade failed or timed out"
    fi

    log_event "System upgrade completed successfully"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "System upgraded successfully. Reboot may be required."
        }'
}

# Main entry point
case "${1:-}" in
    --check)
        check_updates
        ;;
    --upgrade)
        upgrade_system
        ;;
    --upgrade-pkgs)
        shift
        upgrade_packages "$@"
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--check|--upgrade|--upgrade-pkgs <pkg1> [pkg2...]|--version}"
        ;;
esac
