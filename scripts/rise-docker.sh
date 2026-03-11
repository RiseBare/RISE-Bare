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

# Validate port number (1-65535)
validate_port() {
    local port="$1"
    
    # Check if it's a valid number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid port: $port (must be a number)\"}"
        return 1
    fi
    
    # Check range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid port: $port (must be 1-65535)\"}"
        return 1
    fi
    
    return 0
}

# Validate container ID format
validate_container_id() {
    local container_id="$1"
    
    # Container IDs can be:
    # - Full 64-character hex string
    # - Shortened unique prefix (alphanumeric, dots, hyphens, underscores)
    if [[ ! "$container_id" =~ ^[a-fA-F0-9]{64}$ ]] && \
       [[ ! "$container_id" =~ ^[a-zA-Z0-9_.\-]{1,128}$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid container ID format: $container_id\"}"
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

# Validate container name (alphanumeric, dots, hyphens, underscores, 1-128 chars)
validate_container_name() {
    local name="$1"
    
    if [ ${#name} -lt 1 ] || [ ${#name} -gt 128 ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid container name: $name (must be 1-128 characters)\"}"
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z0-9_.\-]+$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid container name: $name (must be alphanumeric, dots, hyphens, underscores)\"}"
        return 1
    fi
    
    return 0
}

# Validate image name
validate_image_name() {
    local image="$1"
    
    # Basic image name validation (repo/image:tag or image:tag)
    if [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*(:[a-zA-Z0-9._-]+)?$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid image name: $image\"}"
        return 1
    fi
    
    return 0
}

# Check if Docker daemon is running
check_docker_daemon() {
    if ! docker info >/dev/null 2>&1; then
        die ERR_DOCKER_DAEMON "Docker daemon is not running"
    fi
}

# Check if container exists
container_exists() {
    local container_id="$1"
    
    if ! docker inspect "$container_id" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

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

# Feature: --update (pull latest image and restart)
update_container() {
    local container_id="$1"

    # Validate container ID format
    local id_validation=$(validate_container_id "$container_id")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_INPUT "$id_validation"
    fi

    # Verify container exists
    if ! docker inspect "$container_id" >/dev/null 2>&1; then
        die ERR_CONTAINER_NOT_FOUND "Container not found: $container_id"
    fi

    # Get container image
    local image=$(docker inspect --format='{{.Config.Image}}' "$container_id" 2>/dev/null)
    
    # Pull latest image
    if ! docker pull "$image" >/dev/null 2>&1; then
        die ERR_DOCKER_COMMAND "Failed to pull latest image: $image"
    fi

    # Restart container
    if ! docker restart "$container_id" >/dev/null 2>&1; then
        die ERR_DOCKER_COMMAND "Failed to restart container: $container_id"
    fi

    log_event "Docker update: ${container_id} (image: ${image})"

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg container "$container_id" \
        --arg image "$image" \
        '{status: "success", api_version: $api_version, message: ("Container updated with image: " + $image)}'
}

# Feature: --logs (get container logs)
get_logs() {
    local container_id="$1"
    local tail="${2:-100}"  # Default to last 100 lines

    # Validate container ID format
    local id_validation=$(validate_container_id "$container_id")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_INPUT "$id_validation"
    fi

    # Verify container exists
    if ! docker inspect "$container_id" >/dev/null 2>&1; then
        die ERR_CONTAINER_NOT_FOUND "Container not found: $container_id"
    fi

    # Validate tail parameter
    if ! [[ "$tail" =~ ^[0-9]+$ ]] || [ "$tail" -lt 1 ]; then
        die ERR_INVALID_INPUT "Invalid tail value: $tail (must be a positive number)"
    fi

    # Get logs
    local logs=$(docker logs --tail "$tail" "$container_id" 2>&1)
    
    # Escape special characters for JSON
    logs=$(echo "$logs" | jq -Rs '.')

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg container "$container_id" \
        --argjson logs "$logs" \
        '{status: "success", api_version: $api_version, container: $container, logs: $logs}'
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
    --update)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Missing container ID"
        update_container "$2"
        ;;
    --logs)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Missing container ID"
        get_logs "$2" "${3:-100}"
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--status|--list|--start|--stop|--restart|--update|--logs <id> [tail]|--version}"
        ;;
esac
