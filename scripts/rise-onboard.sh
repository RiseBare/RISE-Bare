#!/bin/bash
# Script: rise-onboard.sh
# Version: 1.0.0
# Description: RISE Server Onboarding - secure server enrollment with OTP

set -Eeuo pipefail

readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

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

TMPFILE=$(mktemp /tmp/rise-onboard-XXXXXX)

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

    logger -t "$(basename "$0")" -p user.error "$code: $message" 2>/dev/null || true

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
command -v openssl >/dev/null 2>&1 || die ERR_DEPENDENCY "openssl not installed" 2

# Check if running as root for most operations
require_root() {
    [ "$EUID" -eq 0 ] || die ERR_PERMISSION "must be run as root"
}

# V5.9: Validate public key format
validate_pubkey() {
    local pubkey="$1"

    # Check general format: <type> <base64> [optional comment]
    if [[ ! "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]{50,}([[:space:]].*)?$ ]]; then
        return 1
    fi

    # Use ssh-keygen to validate format
    if command -v ssh-keygen >/dev/null 2>&1; then
        if ! echo "$pubkey" | ssh-keygen -l -f /dev/stdin >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}

# Feature: --generate-otp
generate_otp() {
    require_root
    local otp_ttl="${1:-600}"  # 10 minutes default

    # Generate random 6-digit OTP
    local otp
    otp=$(openssl rand -base64 3 | tr -dc '0-9' | head -c 6)

    # Store OTP hash with timestamp
    local otp_hash=$(echo -n "$otp" | sha256sum | awk '{print $1}')
    echo "$otp_hash $(date +%s)" > /var/lib/rise/onboard-otp-hash
    chmod 600 /var/lib/rise/onboard-otp-hash

    # Create temporary SSH config to allow password auth for root
    cat > /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf << 'ONBOARD_EOF'
# RISE Temporary Onboarding Configuration
# This file is automatically removed after onboarding completion
# or after 10 minutes

Match User root
  PasswordAuthentication yes
Match User *
  PasswordAuthentication no
Match all
ONBOARD_EOF

    chmod 600 /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf

    # Reload SSH if running
    if pgrep -x sshd > /dev/null; then
        systemctl reload sshd 2>/dev/null || true
    fi

    # V5.9: Enhanced cleanup timer
    if command -v systemd-run &>/dev/null; then
        systemd-run --on-active=${otp_ttl}s --unit=rise-onboard-cleanup.service \
            /bin/sh -c "rm -f /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf /var/lib/rise/onboard-otp-hash && systemctl reload sshd && logger -t rise-onboard 'OTP expired and cleaned up'" \
            >/dev/null 2>&1

        log_event "OTP generated with automatic cleanup in ${otp_ttl}s"
    elif command -v at &>/dev/null; then
        echo "/usr/local/bin/rise-onboard.sh --cleanup && logger -t rise-onboard 'OTP expired (via at)'" | \
            at now + $((otp_ttl/60)) minutes 2>/dev/null || true

        log_event "OTP generated with 'at' cleanup fallback"
    else
        log_event "WARNING: No timer available for OTP cleanup - manual cleanup required"
    fi

    # Output OTP to stderr ONLY (not stdout)
    echo "======================================" >&2
    echo "    RISE SERVER ONBOARDING OTP       " >&2
    echo "======================================" >&2
    echo "" >&2
    echo "OTP: $otp" >&2
    echo "Valid for: $((otp_ttl/60)) minutes" >&2
    echo "" >&2
    echo "Enter this OTP in the RISE client to complete onboarding." >&2
    echo "======================================" >&2

    # Return success JSON to stdout
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson ttl "$otp_ttl" \
        '{
            status: "success",
            api_version: $api_version,
            otp_ttl_seconds: $ttl,
            message: "OTP generated. Check stderr for the OTP value."
        }'
}

# Feature: --finalize
finalize_onboarding() {
    require_root
    local pubkey="$1"

    # V5.9: Validate public key format BEFORE creating user
    if ! validate_pubkey "$pubkey"; then
        die ERR_INVALID_PUBKEY "Invalid SSH public key format (must be ssh-ed25519, ssh-rsa, or ecdsa-sha2-nistp*)"
    fi

    # Verify OTP was generated
    if [ ! -f /var/lib/rise/onboard-otp-hash ]; then
        die ERR_ONBOARDING_FAILED "No active OTP found. Run --generate-otp first."
    fi

    # Check OTP hasn't expired
    local otp_timestamp=$(awk '{print $2}' /var/lib/rise/onboard-otp-hash)
    local current_time=$(date +%s)
    local otp_age=$((current_time - otp_timestamp))

    if [ "$otp_age" -gt 600 ]; then
        rm -f /var/lib/rise/onboard-otp-hash
        die ERR_OTP_EXPIRED "OTP expired (${otp_age}s old). Generate a new one."
    fi

    # Create rise-admin user if doesn't exist
    if ! id rise-admin &>/dev/null; then
        useradd -m -s /bin/bash rise-admin
        log_event "Created rise-admin user"
    fi

    # Create .ssh directory
    mkdir -p /home/rise-admin/.ssh
    chmod 700 /home/rise-admin/.ssh

    # Add public key to authorized_keys (APPEND - allow multiple devices)
    echo "$pubkey" >> /home/rise-admin/.ssh/authorized_keys
    chmod 600 /home/rise-admin/.ssh/authorized_keys
    chown -R rise-admin:rise-admin /home/rise-admin/.ssh

    log_event "Added SSH public key for rise-admin"

    # Create sudoers file
    cat > /etc/sudoers.d/rise-admin << 'SUDOERS_EOF'
# RISE Admin - Limited sudo privileges
# Allows running RISE management scripts without password

rise-admin ALL=(ALL) NOPASSWD: /usr/local/bin/rise-firewall.sh
rise-admin ALL=(ALL) NOPASSWD: /usr/local/bin/rise-docker.sh
rise-admin ALL=(ALL) NOPASSWD: /usr/local/bin/rise-update.sh
SUDOERS_EOF

    chmod 440 /etc/sudoers.d/rise-admin

    # Validate sudoers syntax
    if command -v visudo >/dev/null 2>&1; then
        if ! visudo -cf /etc/sudoers.d/rise-admin 2>/dev/null; then
            rm -f /etc/sudoers.d/rise-admin
            die ERR_SUDOERS_INVALID "Generated sudoers file has syntax errors"
        fi
    fi

    log_event "Created sudoers file for rise-admin"

    # Lock rise-admin password (key-only authentication)
    passwd -l rise-admin >/dev/null 2>&1 || true

    # Remove temporary SSH configuration
    rm -f /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf

    # Reload SSH
    if pgrep -x sshd > /dev/null; then
        systemctl reload sshd 2>/dev/null || true
    fi

    # Remove OTP hash
    rm -f /var/lib/rise/onboard-otp-hash

    # Cancel cleanup timer
    systemctl stop rise-onboard-cleanup.service 2>/dev/null || true
    systemctl reset-failed rise-onboard-cleanup.service 2>/dev/null || true

    log_event "Onboarding finalized successfully"

    # Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            user_created: true,
            ssh_key_installed: true,
            sudoers_configured: true,
            message: "Onboarding completed. You can now connect as rise-admin with your SSH key."
        }'
}

# Feature: --cleanup
cleanup_onboarding() {
    require_root

    # Remove temporary SSH config
    rm -f /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf

    # Reload SSH if needed
    if pgrep -x sshd > /dev/null; then
        systemctl reload sshd 2>/dev/null || true
    fi

    # Remove OTP hash file
    rm -f /var/lib/rise/onboard-otp-hash

    # Remove rise-admin user if incomplete
    if id rise-admin &>/dev/null && [ ! -f /home/rise-admin/.ssh/authorized_keys ]; then
        userdel -r rise-admin 2>/dev/null || true
        log_event "Removed incomplete rise-admin user during cleanup"
    fi

    # Remove sudoers file if user was removed
    if ! id rise-admin &>/dev/null; then
        rm -f /etc/sudoers.d/rise-admin
    fi

    log_event "Onboarding cleanup completed"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Cleanup completed - all temporary onboarding files removed"
        }'
}

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

# Feature: --check - Check if RISE is installed
check_installation() {
    local rise_installed=false
    local rise_admin_exists=false
    local ssh_key_installed=false

    # Check if scripts exist
    if [ -f /usr/local/bin/rise-firewall.sh ] && \
       [ -f /usr/local/bin/rise-docker.sh ] && \
       [ -f /usr/local/bin/rise-update.sh ] && \
       [ -f /usr/local/bin/rise-health.sh ]; then
        rise_installed=true
    fi

    # Check if rise-admin user exists with SSH key
    if id rise-admin &>/dev/null; then
        rise_admin_exists=true
        if [ -f /home/rise-admin/.ssh/authorized_keys ] && \
           [ -s /home/rise-admin/.ssh/authorized_keys ]; then
            ssh_key_installed=true
        fi
    fi

    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        --argjson rise_installed "$rise_installed" \
        --argjson rise_admin_exists "$rise_admin_exists" \
        --argjson ssh_key_installed "$ssh_key_installed" \
        '{
            status: "success",
            api_version: $api_version,
            script_version: $script_version,
            rise_installed: $rise_installed,
            rise_admin_exists: $rise_admin_exists,
            ssh_key_installed: $ssh_key_installed
        }'
}

# Feature: --add-device - Add a new SSH key to existing RISE installation
add_device() {
    require_root
    local pubkey="$1"

    # Validate public key
    if ! validate_pubkey "$pubkey"; then
        die ERR_INVALID_PUBKEY "Invalid SSH public key format"
    fi

    # Check if rise-admin exists
    if ! id rise-admin &>/dev/null; then
        die ERR_NO_RISE_ADMIN "RISE is not installed on this server. Run onboarding first."
    fi

    # Create .ssh directory if needed
    mkdir -p /home/rise-admin/.ssh
    chmod 700 /home/rise-admin/.ssh

    # Check if key already exists
    if grep -qF "$pubkey" /home/rise-admin/.ssh/authorized_keys 2>/dev/null; then
        jq -n \
            --arg api_version "$API_VERSION" \
            '{
                status: "success",
                api_version: $api_version,
                message: "SSH key already registered for this device",
                already_exists: true
            }'
        exit 0
    fi

    # Append key to authorized_keys (ADD not replace!)
    echo "$pubkey" >> /home/rise-admin/.ssh/authorized_keys
    chmod 600 /home/rise-admin/.ssh/authorized_keys
    chown -R rise-admin:rise-admin /home/rise-admin/.ssh

    log_event "Added new SSH key for rise-admin (device added)"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "New SSH key added successfully",
            already_exists: false
        }'
}

# Feature: --remove-device - Remove an SSH key from authorized_keys
remove_device() {
    require_root
    local pubkey="$1"

    if ! id rise-admin &>/dev/null; then
        die ERR_NO_RISE_ADMIN "RISE is not installed"
    fi

    if [ ! -f /home/rise-admin/.ssh/authorized_keys ]; then
        die ERR_NO_KEYS "No authorized keys found"
    fi

    # Remove the key
    local key_count_before=$(wc -l < /home/rise-admin/.ssh/authorized_keys)
    grep -vF "$pubkey" /home/rise-admin/.ssh/authorized_keys > /tmp/authorized_keys_tmp
    mv /tmp/authorized_keys_tmp /home/rise-admin/.ssh/authorized_keys
    chmod 600 /home/rise-admin/.ssh/authorized_keys
    chown -R rise-admin:rise-admin /home/rise-admin/.ssh
    local key_count_after=$(wc -l < /home/rise-admin/.ssh/authorized_keys)

    log_event "Removed SSH key from rise-admin"

    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson removed $((key_count_before - key_count_after)) \
        '{
            status: "success",
            api_version: $api_version,
            message: "SSH key removed",
            keys_remaining: $removed
        }'
}

# Feature: --list-devices - List all registered SSH keys
list_devices() {
    if ! id rise-admin &>/dev/null; then
        die ERR_NO_RISE_ADMIN "RISE is not installed"
    fi

    if [ ! -f /home/rise-admin/.ssh/authorized_keys ]; then
        jq -n \
            --arg api_version "$API_VERSION" \
            '{
                status: "success",
                api_version: $api_version,
                devices: []
            }'
        exit 0
    fi

    # Parse keys and extract info
    local devices_json="["
    local first=true
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local key_type=$(echo "$line" | awk '{print $1}')
        local key_comment=$(echo "$line" | awk '{print $3}' | sed 's/"/\\"/g')

        if [ "$first" = true ]; then
            first=false
        else
            devices_json+=","
        fi

        devices_json+="{\"type\":\"$key_type\",\"comment\":\"$key_comment\",\"key\":\"${line:0:80}...\"}"
    done < /home/rise-admin/.ssh/authorized_keys
    devices_json+="]"

    echo "$devices_json" | jq \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            devices: .
        }'
}

# Main entry point
case "${1:-}" in
    --check)
        check_installation
        ;;
    --add-device)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Usage: $0 --add-device <public_key>"
        add_device "$2"
        ;;
    --remove-device)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Usage: $0 --remove-device <public_key>"
        remove_device "$2"
        ;;
    --list-devices)
        list_devices
        ;;
    --generate-otp)
        generate_otp "${2:-600}"
        ;;
    --finalize)
        [ -n "${2:-}" ] || die ERR_INVALID_ARGUMENTS "Usage: $0 --finalize <public_key>"
        finalize_onboarding "$2"
        ;;
    --cleanup)
        cleanup_onboarding
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--check|--add-device <pubkey>|--remove-device <pubkey>|--list-devices|--generate-otp|--finalize <pubkey>|--cleanup|--version}"
        ;;
esac
