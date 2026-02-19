#!/bin/bash
# Script: rise-firewall.sh
# Version: 1.0.0
# Description: RISE Firewall Management - atomic rule application with automatic rollback

set -Eeuo pipefail

# API version (major.minor) - must match client expectation
readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

# Locale enforcement (prevent localized command output)
export LANG=C
export LC_ALL=C

# flock on FD 200 (convention: use 200-209 for custom file descriptors)
# Prevents concurrent RISE operations which could corrupt state files
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

# Temporary file for atomic operations (cleaned up by trap)
TMPFILE=$(mktemp /tmp/rise-firewall-XXXXXX)

# Cleanup handler (called on EXIT, ERR, INT, TERM)
cleanup() {
    local exit_code=$?
    rm -f "$TMPFILE"
    flock -u 200 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT ERR INT TERM

# Error handler with JSON output
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

# Logging function
log_event() {
    logger -t "$(basename "$0")" -p user.info "$*"
}

# Dependency checks
for cmd in jq nft ss timeout; do
    command -v "$cmd" >/dev/null 2>&1 || die ERR_DEPENDENCY "$cmd not installed" 2
done

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

# Validate CIDR format (IPv4 only)
validate_cidr() {
    local cidr="$1"

    # Reject IPv6 immediately (contains ":")
    if [[ "$cidr" == *:* ]]; then
        return 1
    fi

    # Must match x.x.x.x/nn pattern
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi

    # Validate each octet (0-255)
    IFS='.' read -r -a octets <<< "${cidr%/*}"
    for octet in "${octets[@]}"; do
        [ "$octet" -le 255 ] || return 1
    done

    # Validate prefix length (0-32)
    local prefix="${cidr#*/}"
    [ "$prefix" -le 32 ] || return 1

    return 0
}

# Feature: --scan with IPv6 Support (V5.9)
scan_ports() {
    # Get nftables rules as JSON
    local nft_output
    local nft_exit

    nft_output=$(nft -j list chain inet rise_filter input 2>&1)
    nft_exit=$?

    # Validate nftables output
    if [ $nft_exit -ne 0 ]; then
        if [[ "$nft_output" =~ "No such file or directory" ]] || [[ "$nft_output" =~ "does not exist" ]]; then
            nft_output='{}'
        else
            die ERR_OPERATION_FAILED "nftables error: ${nft_output}"
        fi
    fi

    # Validate JSON structure
    if ! echo "$nft_output" | jq empty 2>/dev/null; then
        die ERR_OPERATION_FAILED "nftables returned invalid JSON"
    fi

    # Parse listening ports with IPv4/IPv6 support
    local ports_json="[]"
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        local proto=$(echo "$line" | awk '{print $1}')
        local local_addr=$(echo "$line" | awk '{print $5}')

        # V5.9: Robust parsing for IPv4 and IPv6
        local port=""
        local listen_ip=""

        if [[ "$local_addr" =~ ^\[(.+)\]:([0-9]+)$ ]]; then
            # IPv6 format: [::1]:22 or [2001:db8::1]:443
            listen_ip="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
        elif [[ "$local_addr" =~ ^([^:]+):([0-9]+)$ ]]; then
            # IPv4 format: 0.0.0.0:22 or 192.168.1.1:80
            listen_ip="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
        elif [[ "$local_addr" =~ ^(.+):([0-9]+)$ ]]; then
            # Fallback for IPv6 without brackets
            listen_ip="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Validate that port is a valid number
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            continue
        fi

        # Improved process name parsing
        local process=$(echo "$line" | awk -F'users:\\(\\("' '{print $2}' | cut -d'"' -f1)
        [ -z "$process" ] && process="unknown"

        # Determine firewall status from nft JSON
        local status=$(echo "$nft_output" | jq -r --arg port "$port" --arg proto "$proto" '
            .nftables[]? | select(.rule?) | .rule |
            select(.expr[]? | select(.match?) | .match.right == ($port | tonumber) and
                   .match.left.payload.protocol == $proto) |
            .expr[] | select(.accept? or .drop?) |
            if .accept then "allow" elif .drop then "block" else "unknown" end
        ' | head -n1)

        [ -z "$status" ] && status="unknown"

        # Build JSON object for this port
        local port_obj=$(jq -n \
            --argjson port "$port" \
            --arg proto "$proto" \
            --arg process "$process" \
            --arg listening_ip "$listen_ip" \
            --arg status "$status" \
            '{port: $port, proto: $proto, process: $process, listening_ip: $listening_ip, status: $status}')

        ports_json=$(echo "$ports_json" | jq --argjson obj "$port_obj" '. += [$obj]')
    done < <(ss -tulpnH 2>/dev/null || true)

    # Output final JSON
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson data "$ports_json" \
        '{status: "success", api_version: $api_version, data: $data}'
}

# Feature: --apply with systemd cleanup (V5.9)
apply_rules() {
    # 1. Read and validate JSON input
    local rules
    rules=$(cat)
    echo "$rules" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # 2. Validate all rules structure with jq
    jq -e '
        if type != "array" then error("Payload must be array") else . end |
        .[] |
        if (.port | type) != "number" or .port < 1 or .port > 65535
            then error("Port out of range") else . end |
        if .proto != "tcp" and .proto != "udp"
            then error("proto must be tcp or udp") else . end |
        if .action != "allow" and .action != "drop"
            then error("action must be allow or drop") else . end
    ' <<< "$rules" >/dev/null 2>&1 \
        || die ERR_INVALID_RULE "Rule validation failed (port/proto/action)"

    # 3. Validate CIDR fields
    while IFS= read -r rule; do
        cidr=$(jq -r '.cidr // empty' <<< "$rule")
        if [ -n "$cidr" ] && ! validate_cidr "$cidr"; then
            die ERR_INVALID_RULE "Invalid CIDR: $cidr (IPv4 only, format x.x.x.x/nn)"
        fi
    done < <(jq -c '.[]' <<< "$rules")

    # 4. Build complete nftables ruleset file
    cat > "$TMPFILE" << 'EOF'
#!/usr/sbin/nft -f
# RISE Firewall Rules - Atomic Application
# DO NOT EDIT - Managed by rise-firewall.sh

flush table inet rise_filter

table inet rise_filter {
  chain input {
    type filter hook input priority filter - 10; policy drop;

    # Default safe rules (always allowed)
    ct state established,related accept
    iif lo accept

    # ICMP/ICMPv6 (ping, traceroute)
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    # User-defined rules below
EOF

    # 5. Generate nftables rules from JSON
    while IFS= read -r rule; do
        port=$(jq -r '.port' <<< "$rule")
        proto=$(jq -r '.proto' <<< "$rule")
        action=$(jq -r '.action' <<< "$rule")
        cidr=$(jq -r '.cidr // empty' <<< "$rule")

        if [ "$action" = "allow" ]; then
            nft_action="accept"
        else
            nft_action="drop"
        fi

        if [ -n "$cidr" ]; then
            echo "        ip saddr $cidr $proto dport $port $nft_action" >> "$TMPFILE"
        else
            echo "        $proto dport $port $nft_action" >> "$TMPFILE"
        fi
    done < <(jq -c '.[]' <<< "$rules")

    # Close the ruleset
    cat >> "$TMPFILE" << 'EOF'
  }
}
EOF

    # 6. Apply atomically (single nft -f command)
    if ! nft -f "$TMPFILE" 2>&1; then
        die ERR_OPERATION_FAILED "Failed to apply nftables rules"
    fi

    log_event "Firewall rules applied ($(jq 'length' <<< "$rules") rules)"

    # 7. Save pending rules for confirm (NOT to persistent file yet)
    cp "$TMPFILE" /var/lib/rise/pending-rules.nft
    chmod 600 /var/lib/rise/pending-rules.nft

    # 8. Schedule auto-rollback (60 seconds) with cleanup (V5.9)
    local rollback_scheduled="false"
    local warning=""

    if command -v systemd-run >/dev/null 2>&1; then
        # V5.9: Clean up any existing rollback service first
        systemctl stop rise-firewall-rollback.service 2>/dev/null || true
        systemctl reset-failed rise-firewall-rollback.service 2>/dev/null || true

        # Launch new rollback timer
        systemd-run --on-active=60s --unit=rise-firewall-rollback.service \
            /usr/local/bin/rise-firewall.sh --rollback >/dev/null 2>&1
        rollback_scheduled="true"
    else
        warning="Auto-rollback unavailable: systemd-run not found"
        log_event "WARNING: ${warning}"
    fi

    # 9. Return success with metadata
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg rollback_scheduled "$rollback_scheduled" \
        --arg warning "$warning" \
        '{
            status: "success",
            api_version: $api_version,
            rollback_scheduled: ($rollback_scheduled == "true"),
            warning: (if $warning != "" then $warning else null end),
            message: "Rules applied. Confirm within 60s to persist."
        }'
}

# Feature: --confirm
confirm_rules() {
    local pending_file="/var/lib/rise/pending-rules.nft"

    # 1. Check if pending file exists
    if [ ! -f "$pending_file" ]; then
        die ERR_OPERATION_FAILED "No pending ruleset found (already confirmed or rolled back)"
    fi

    # 2. Check file age (must be < 90s to prevent stale confirmation)
    local file_age=$(($(date +%s) - $(stat -c %Y "$pending_file" 2>/dev/null || echo "0")))
    if [ "$file_age" -gt 90 ]; then
        rm -f "$pending_file"
        die ERR_PENDING_EXPIRED "Pending rules expired (${file_age}s old). Re-apply with --apply."
    fi

    # 3. Cancel rollback timer
    systemctl stop rise-firewall-rollback.service 2>/dev/null || true
    systemctl reset-failed rise-firewall-rollback.service 2>/dev/null || true

    # 4. Persist rules to drop-in file
    local persistent_file="/etc/nftables.d/rise-rules.nft"
    cp "$pending_file" "$persistent_file"
    chmod 644 "$persistent_file"

    # 5. Clean up pending file
    rm -f "$pending_file"

    log_event "Firewall rules confirmed and persisted"

    # 6. Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            persisted: true,
            message: "Rules confirmed and will persist across reboots"
        }'
}

# Feature: --rollback
rollback_rules() {
    local persistent_file="/etc/nftables.d/rise-rules.nft"

    # Check if persistent rules exist
    if [ -f "$persistent_file" ]; then
        # Restore from persistent file
        if ! nft -f "$persistent_file" 2>&1; then
            die ERR_OPERATION_FAILED "Failed to restore persisted rules"
        fi
        log_event "Rules rolled back to persisted state"
    else
        # Flush table if no persisted rules
        nft flush table inet rise_filter 2>/dev/null || true
        log_event "Rules rolled back (table flushed)"
    fi

    # Clean up pending file
    rm -f /var/lib/rise/pending-rules.nft

    # Cancel rollback timer if running
    systemctl stop rise-firewall-rollback.service 2>/dev/null || true

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Rules rolled back"
        }'
}

# Feature: --flush
flush_rules() {
    nft flush table inet rise_filter 2>/dev/null || true
    rm -f /var/lib/rise/pending-rules.nft /etc/nftables.d/rise-rules.nft

    log_event "Firewall rules flushed"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "All RISE firewall rules flushed"
        }'
}

# Main entry point
case "${1:-}" in
    --scan)
        scan_ports
        ;;
    --apply)
        apply_rules
        ;;
    --confirm)
        confirm_rules
        ;;
    --rollback)
        rollback_rules
        ;;
    --flush)
        flush_rules
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--scan|--apply|--confirm|--rollback|--flush|--version}"
        ;;
esac
