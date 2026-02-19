#!/usr/bin/env bash
# setup-env.sh - RISE Environment Setup Script
# Version: 1.0.0
# Description: Install dependencies and manage script updates for RISE

set -Eeuo pipefail

readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Error handler
die() {
    local error_code="$1"
    shift
    local message="$*"

    # Log to syslog
    logger -t setup-env -p user.error "$error_code: $message" 2>/dev/null || true

    # Output JSON
    jq -n \
        --arg status "error" \
        --arg error_code "$error_code" \
        --arg message "$message" \
        --arg api_version "$API_VERSION" \
        '{status: $status, error_code: $error_code, message: $message, api_version: $api_version}'

    exit 1
}

# Logging function
log_event() {
    logger -t setup-env -p user.info "$*" 2>/dev/null || true
}

# Install dependencies
install_dependencies() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        die ERR_PERMISSION "This script must be run as root"
    fi

    # Update package lists
    apt-get update -qq 2>/dev/null || die ERR_OPERATION_FAILED "apt-get update failed"

    # Install required packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        jq \
        nftables \
        curl \
        util-linux \
        openssl \
        psmisc \
        dnsutils \
        ca-certificates \
        || die ERR_OPERATION_FAILED "Failed to install dependencies"

    # V5.9: Create system directories required by RISE scripts
    # /var/lib/rise: Storage for temporary states (pending rules, OTP hash)
    # /var/lock: Lock files for flock (may not exist on minimal systems)
    mkdir -p /var/lib/rise /var/lock
    chmod 755 /var/lib/rise /var/lock

    # Create nftables drop-in directory
    mkdir -p /etc/nftables.d
    chmod 755 /etc/nftables.d

    # Verify nftables supports JSON output (-j flag)
    if ! nft -j list ruleset >/dev/null 2>&1; then
        die ERR_DEPENDENCY "nftables version too old (requires -j flag support)"
    fi

    log_event "Dependencies installed and directories created"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, message: "Dependencies installed and directories created"}'
}

# Update scripts from GitHub
update_scripts() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        die ERR_PERMISSION "This script must be run as root"
    fi

    # Check network connectivity first
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null 2>&1; then
        die ERR_NETWORK "Cannot connect to GitHub"
    fi

    # Manifest URL - customize this for your repository
    MANIFEST_URL="https://raw.githubusercontent.com/RiseBare/RISE-Specs/main/manifest.sha256"
    local manifest_file="/tmp/rise-manifest.json"

    curl -s -f -o "$manifest_file" "$MANIFEST_URL" 2>/dev/null \
        || die ERR_NETWORK "Failed to download manifest.json"

    # Validate JSON structure
    jq empty < "$manifest_file" 2>/dev/null \
        || die ERR_VALIDATION_FAILED "manifest.json is not valid JSON"

    # Create temporary directory for atomic updates
    local tmpdir=$(mktemp -d /tmp/rise-update-XXXXXX)
    trap "rm -rf '$tmpdir' '$manifest_file'" EXIT

    # For each script in manifest
    while IFS=$'\t' read -r script_name script_version remote_sha url; do
        # Get local version and checksum
        local script_path="/usr/local/bin/${script_name}"
        local local_version=""
        local local_sha=""

        if [ -f "$script_path" ]; then
            local_version=$(bash "$script_path" --version 2>/dev/null | jq -r '.script_version // empty' || echo "")
            local_sha=$(sha256sum "$script_path" | awk '{print $1}')
        fi

        # Compare versions and checksums
        if [ "$script_version" != "$local_version" ]; then
            echo "Updating ${script_name}: ${local_version:-none} -> ${script_version}" >&2

            # Download to temp directory (not directly to /usr/local/bin)
            curl -s -f -o "$tmpdir/${script_name}" "$url" \
                || die ERR_NETWORK "Failed to download ${script_name}"

            # Verify checksum
            local downloaded_sha=$(sha256sum "$tmpdir/${script_name}" | awk '{print $1}')
            if [ "$downloaded_sha" != "$remote_sha" ]; then
                die ERR_VALIDATION "Checksum mismatch for ${script_name} (expected: ${remote_sha}, got: ${downloaded_sha})"
            fi

            # Make executable
            chmod 755 "$tmpdir/${script_name}"

            # Atomic move (replaces existing file in single operation)
            mv -f "$tmpdir/${script_name}" "$script_path"

            echo "Updated ${script_name} to version ${script_version}" >&2

        elif [ "$local_sha" != "$remote_sha" ]; then
            # Version matches but hash differs = tampering detected
            die ERR_VALIDATION "SECURITY: ${script_name} version ${script_version} hash mismatch (tampered?)"
        fi
    done < <(jq -r '.scripts[] | [.name, .version, .sha256, .url] | @tsv' "$manifest_file" 2>/dev/null || echo "")

    log_event "Scripts updated successfully"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, message: "Scripts updated successfully"}'
}

# Main entry point
case "${1:-}" in
    --install)
        install_dependencies
        ;;
    --update)
        update_scripts
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--install|--update|--version}"
        ;;
esac
