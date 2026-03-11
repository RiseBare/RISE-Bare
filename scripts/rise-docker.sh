#!/bin/bash
# Script: rise-docker.sh
# Version: 1.0.0
# Description: RISE Docker Management - container lifecycle control

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

TMPFILE=$(mktemp /tmp/rise-docker-XXXXXX)

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
command -v jq >/dev/null 2>&1 || die ERR_DEPENDENCY "jq not installed" 2

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, data: {installed: false}}'
    exit 0
fi

# Must be root for Docker operations
[ "$EUID" -eq 0 ] || die ERR_PERMISSION "must be run as root"

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, data: {installed: true, daemon_running: false}}'
    exit 0
fi

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

# Feature: --status
status_docker() {
    local version
    version=$(docker version --format '{{json .Server.Version}}' 2>/dev/null | jq -r . || echo "unknown")

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg version "$version" \
        '{
            status: "success",
            api_version: $api_version,
            data: {
                installed: true,
                daemon_running: true,
                version: $version
            }
        }'
}

# Feature: --list
list_containers() {
    # Check if any containers exist
    local container_ids
    container_ids=$(docker ps -aq 2>/dev/null || true)

    if [ -z "$container_ids" ]; then
        jq -n \
            --arg api_version "$API_VERSION" \
            '{status: "success", api_version: $api_version, data: []}'
        exit 0
    fi

    # Get full container details via docker inspect
    local containers_raw
    containers_raw=$(echo "$container_ids" | xargs -r docker inspect 2>/dev/null | jq -s 'add // []' || echo '[]')

    # Parse containers with jq (sanitizes all fields automatically)
    local containers_json
    containers_json=$(echo "$containers_raw" | jq -c '
        [.[] | {
            id: .Id[:12],
            name: (.Name | ltrimstr("/")),
            state: .State.Status,
            status_text: .State.Status,
            image: .Config.Image,
            compose_path: (.Config.Labels["com.docker.compose.project.working_dir"] // null)
        }]
    ')

    # Output final JSON
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson data "$containers_json" \
        '{status: "success", api_version: $api_version, data: $data}'
}

# Feature: --start, --stop, --restart
container_action() {
    local action="$1"
    local container_id="$2"

    # Validate container ID format (alphanumeric, dots, hyphens, underscores only)
    if ! [[ "$container_id" =~ ^[a-zA-Z0-9_.\-]{1,128}$ ]]; then
        die ERR_INVALID_INPUT "Invalid container ID format: $container_id"
    fi

    # Verify container exists
    if ! docker inspect "$container_id" >/dev/null 2>&1; then
        die ERR_CONTAINER_NOT_FOUND "Container not found: $container_id"
    fi

    # Execute action
    if ! docker "$action" "$container_id" >/dev/null 2>&1; then
        die ERR_DOCKER_COMMAND "docker $action $container_id failed"
    fi

    log_event "Docker ${action}: ${container_id}"

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg action "$action" \
        '{status: "success", api_version: $api_version, message: ("Container " + $action + " successful")}'
}

# Main entry point
case "${1:-}" in
    --status)
        status_docker
        ;;
    --list)
        list_containers
        ;;
    --start|--stop|--restart)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Missing container ID"
        container_action "${1#--}" "$2"
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--status|--list|--start|--stop|--restart <id>|--version}"
        ;;
esac
