#!/usr/bin/env bash
# rise-health.sh - RISE Health Check Script
# Version: 1.0.0
# Description: Server health monitoring without root privileges

readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Verify jq is installed BEFORE first use
if ! command -v jq >/dev/null 2>&1; then
    printf '{"status":"error","api_version":"%s","code":"ERR_DEPENDENCY","message":"jq not installed"}\n' \
        "${API_VERSION}"
    exit 2
fi

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

# Check: Sudoers file exists with correct permissions (V5.9 - simplified)
check_sudoers_file() {
    local file="/etc/sudoers.d/rise-admin"

    # Check existence
    if [ ! -f "$file" ]; then
        echo "fail"
        return
    fi

    # Check permissions (must be 0440 or 0400 for sudo to accept)
    local perms
    perms=$(stat -c %a "$file" 2>/dev/null || echo "000")
    if [ "$perms" != "440" ] && [ "$perms" != "400" ]; then
        echo "fail"
        return
    fi

    # V5.9: Removed visudo syntax check - see SPEC for rationale
    echo "pass"
}

# Check: No temporary SSH onboarding config remains
check_ssh_dropin_clean() {
    if [ -f /etc/ssh/sshd_config.d/99-rise-onboard-temp.conf ]; then
        echo "fail"
    else
        echo "pass"
    fi
}

# Check: Nftables includes drop-in directory
check_nftables_include() {
    if grep -q 'include "/etc/nftables.d/\*.nft"' /etc/nftables.conf 2>/dev/null || \
       grep -q 'include "/etc/nftables.d/\*.rules"' /etc/nftables.conf 2>/dev/null; then
        echo "pass"
    else
        echo "fail"
    fi
}

# Check: All RISE scripts are present
check_scripts_present() {
    local scripts=(rise-firewall.sh rise-docker.sh rise-update.sh rise-onboard.sh)
    for script in "${scripts[@]}"; do
        if [ ! -f "/usr/local/bin/${script}" ]; then
            echo "fail"
            return
        fi
    done
    echo "pass"
}

# Build health status JSON
jq -n \
    --arg api_version "$API_VERSION" \
    --arg sudoers_file "$(check_sudoers_file)" \
    --arg ssh_dropin_clean "$(check_ssh_dropin_clean)" \
    --arg nftables_include "$(check_nftables_include)" \
    --arg scripts_present "$(check_scripts_present)" \
    '{
        status: "success",
        api_version: $api_version,
        checks: {
            sudoers_file: $sudoers_file,
            ssh_dropin_clean: $ssh_dropin_clean,
            nftables_include: $nftables_include,
            scripts_present: $scripts_present
        }
    }'
