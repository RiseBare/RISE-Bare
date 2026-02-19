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

# Dependency checks
command -v apt-get >/dev/null 2>&1 || die ERR_DEPENDENCY "apt-get not found"
command -v jq >/dev/null 2>&1 || die ERR_DEPENDENCY "jq not found"
command -v fuser >/dev/null 2>&1 || die ERR_DEPENDENCY "fuser not found"
[ "$EUID" -eq 0 ] || die ERR_PERMISSION "must be run as root"

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
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--check|--upgrade|--version}"
        ;;
esac
