#!/bin/bash
# Script: rise-firewall.sh
# Version: 2.0.0
# Description: RISE Firewall Management - atomic rule application with automatic rollback
#              Fixed: SSH injection vulnerabilities, implemented actual CRUD operations

set -Eeuo pipefail

# API version (major.minor) - must match client expectation
readonly API_VERSION="2.0"
readonly SCRIPT_VERSION="2.0.0"

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
        local process=$(echo "$line" | awk -F'users:\\\\(\\("' '{print $2}' | cut -d'"' -f1)
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
    local rules_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rules_json=$(echo "${2}" | base64 -d)
    else
        rules_json=$(cat)
    fi
    
    echo "$rules_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate all rules structure with jq
    jq -e '
        if type != "array" then error("Payload must be array") else . end |
        .[] |
        if (.port | type) != "number" or .port < 1 or .port > 65535
            then error("Port out of range") else . end |
        if .proto != "tcp" and .proto != "udp"
            then error("proto must be tcp or udp") else . end |
        if .action != "allow" and .action != "drop"
            then error("action must be allow or drop") else . end
    ' <<< "$rules_json" >/dev/null 2>&1 \
        || die ERR_INVALID_RULE "Rule validation failed (port/proto/action)"

    # Validate CIDR fields
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

# Feature: --list-rules
list_rules() {
    # Get nftables rules as JSON
    local nft_output
    local nft_exit

    nft_output=$(nft -j list chain inet rise_filter input 2>&1)
    nft_exit=$?

    # Validate nftables output
    if [ $nft_exit -ne 0 ]; then
        if [[ "$nft_output" =~ "No such file or directory" ]] || [[ "$nft_output" =~ "does not exist" ]] || [[ "$nft_output" =~ "Error:" ]]; then
            nft_output='{}'
        else
            die ERR_OPERATION_FAILED "nftables error: ${nft_output}"
        fi
    fi

    # Validate JSON structure
    if ! echo "$nft_output" | jq empty 2>/dev/null; then
        die ERR_OPERATION_FAILED "nftables returned invalid JSON"
    fi

    # Parse rules and convert to JSON array
    local rules_json="[]"
    
    # Extract rules from nft JSON output
    local rules=$(echo "$nft_output" | jq -r '.nftables[]? | select(.rule?) | .rule' 2>/dev/null)
    
    if [ -n "$rules" ]; then
        # Process each rule
        echo "$rules" | while IFS= read -r rule; do
            # Extract port from expr
            local port=$(echo "$rule" | jq -r '.expr[]? | select(.match?) | .match.right // empty' 2>/dev/null)
            
            # Extract protocol
            local proto=$(echo "$rule" | jq -r '.expr[]? | select(.match?) | .match.left.payload.protocol // empty' 2>/dev/null)
            
            # Extract source IP if present
            local src_ip=$(echo "$rule" | jq -r '.expr[]? | select(.match?) | select(.match.left.payload.type == "ipv4_address") | .match.right // empty' 2>/dev/null)
            
            # Extract action
            local action=$(echo "$rule" | jq -r '.expr[]? | select(.accept? or .drop?) | if .accept then "accept" elif .drop then "drop" else "unknown" end' 2>/dev/null)
            
            # Build rule JSON
            local rule_json=$(jq -n \
                --argjson port "$port" \
                --arg proto "$proto" \
                --arg src_ip "$src_ip" \
                --arg action "$action" \
                '{port: $port, protocol: $proto, sourceIp: ($src_ip | if . == "" then null else . end), action: $action}')
            
            rules_json=$(echo "$rules_json" | jq --argjson obj "$rule_json" '. += [$obj]')
        done
    fi

    # Output final JSON
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson data "$rules_json" \
        '{status: "success", api_version: $api_version, data: $data}'
}

# Feature: --add-rule with base64 support and actual nftables modification
add_rule() {
    local rule_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rule_json=$(echo "${2}" | base64 -d)
    else
        rule_json=$(cat)
    fi
    
    echo "$rule_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate rule structure
    jq -e '
        if (.port | type) != "number" or .port < 1 or .port > 65535
            then error("Port out of range") else . end |
        if .proto != "tcp" and .proto != "udp"
            then error("proto must be tcp or udp") else . end |
        if .action != "allow" and .action != "drop"
            then error("action must be allow or drop") else . end
    ' <<< "$rule_json" >/dev/null 2>&1 \
        || die ERR_INVALID_RULE "Rule validation failed"

    # Validate CIDR if present
    local cidr=$(jq -r '.cidr // empty' <<< "$rule_json")
    if [ -n "$cidr" ] && ! validate_cidr "$cidr"; then
        die ERR_INVALID_RULE "Invalid CIDR: $cidr (IPv4 only, format x.x.x.x/nn)"
    fi

    # Get current rules and backup
    local backup_file="/tmp/rise-firewall-backup-$(date +%s)"
    nft -j list table inet rise_filter > "$backup_file" 2>/dev/null || true

    # Build new ruleset with the new rule added
    local port=$(jq -r '.port' <<< "$rule_json")
    local proto=$(jq -r '.proto' <<< "$rule_json")
    local action=$(jq -r '.action' <<< "$rule_json")
    
    local nft_action="accept"
    [ "$action" = "drop" ] && nft_action="drop"

    # Create temporary ruleset with new rule
    cat > "$TMPFILE" << EOF
#!/usr/sbin/nft -f
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

    # Add existing rules (except the one we're replacing if it exists)
    local existing_rules=$(nft -j list chain inet rise_filter input 2>/dev/null | jq -r '.nftables[]? | select(.rule?) | .rule' 2>/dev/null || echo "")
    
    if [ -n "$existing_rules" ]; then
        echo "$existing_rules" | while IFS= read -r existing_rule; do
            local existing_port=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.right // empty' 2>/dev/null)
            local existing_proto=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.left.payload.protocol // empty' 2>/dev/null)
            
            # Skip if this is the same rule being added
            if [ "$existing_port" = "$port" ] && [ "$existing_proto" = "$proto" ]; then
                continue
            fi
            
            # Reconstruct the nft rule
            local existing_action=$(echo "$existing_rule" | jq -r '.expr[]? | select(.accept? or .drop?) | if .accept then "accept" elif .drop then "drop" else "" end' 2>/dev/null)
            local existing_cidr=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | select(.match.left.payload.type == "ipv4_address") | .match.right // empty' 2>/dev/null)
            
            if [ -n "$existing_cidr" ]; then
                echo "    ip saddr $existing_cidr $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            else
                echo "    $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            fi
        done
    fi

    # Add the new rule
    if [ -n "$cidr" ]; then
        echo "    ip saddr $cidr $proto dport $port $nft_action" >> "$TMPFILE"
    else
        echo "    $proto dport $port $nft_action" >> "$TMPFILE"
    fi

    # Close the ruleset
    cat >> "$TMPFILE" << 'EOF'
  }
}
EOF

    # Apply atomically
    if ! nft -f "$TMPFILE" 2>&1; then
        # Rollback on failure
        if [ -f "$backup_file" ]; then
            nft -f "$backup_file" 2>/dev/null || true
        fi
        die ERR_OPERATION_FAILED "Failed to add firewall rule"
    fi

    rm -f "$backup_file"
    log_event "Firewall rule added (port: $port, proto: $proto)"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Rule added successfully",
            rule: '"$rule_json"'
        }'
}

# Feature: --edit-rule with base64 support and actual nftables modification
edit_rule() {
    local rules_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rules_json=$(echo "${2}" | base64 -d)
    else
        rules_json=$(cat)
    fi
    
    echo "$rules_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Parse the input (first rule is old, second is new)
    local old_port=$(echo "$rules_json" | jq -r '.old.port')
    local old_proto=$(echo "$rules_json" | jq -r '.old.proto')
    local new_port=$(echo "$rules_json" | jq -r '.new.port')
    local new_proto=$(echo "$rules_json" | jq -r '.new.proto')
    local new_action=$(echo "$rules_json" | jq -r '.new.action')
    local new_cidr=$(echo "$rules_json" | jq -r '.new.cidr // empty')

    # Validate new rule
    jq -e '
        if (.new.port | type) != "number" or .new.port < 1 or .new.port > 65535
            then error("Port out of range") else . end |
        if .new.proto != "tcp" and .new.proto != "udp"
            then error("proto must be tcp or udp") else . end |
        if .new.action != "allow" and .new.action != "drop"
            then error("action must be allow or drop") else . end
    ' <<< "$rules_json" >/dev/null 2>&1 \
        || die ERR_INVALID_RULE "New rule validation failed"

    # Validate CIDR if present
    if [ -n "$new_cidr" ] && ! validate_cidr "$new_cidr"; then
        die ERR_INVALID_RULE "Invalid CIDR: $new_cidr (IPv4 only, format x.x.x.x/nn)"
    fi

    # Get current rules and backup
    local backup_file="/tmp/rise-firewall-backup-$(date +%s)"
    nft -j list table inet rise_filter > "$backup_file" 2>/dev/null || true

    # Build new ruleset with the rule updated
    local nft_action="accept"
    [ "$new_action" = "drop" ] && nft_action="drop"

    cat > "$TMPFILE" << EOF
#!/usr/sbin/nft -f
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

    # Add existing rules (except the one we're replacing)
    local existing_rules=$(nft -j list chain inet rise_filter input 2>/dev/null | jq -r '.nftables[]? | select(.rule?) | .rule' 2>/dev/null || echo "")
    
    if [ -n "$existing_rules" ]; then
        echo "$existing_rules" | while IFS= read -r existing_rule; do
            local existing_port=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.right // empty' 2>/dev/null)
            local existing_proto=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.left.payload.protocol // empty' 2>/dev/null)
            
            # Skip if this is the rule being edited
            if [ "$existing_port" = "$old_port" ] && [ "$existing_proto" = "$old_proto" ]; then
                continue
            fi
            
            # Reconstruct the nft rule
            local existing_action=$(echo "$existing_rule" | jq -r '.expr[]? | select(.accept? or .drop?) | if .accept then "accept" elif .drop then "drop" else "" end' 2>/dev/null)
            local existing_cidr=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | select(.match.left.payload.type == "ipv4_address") | .match.right // empty' 2>/dev/null)
            
            if [ -n "$existing_cidr" ]; then
                echo "    ip saddr $existing_cidr $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            else
                echo "    $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            fi
        done
    fi

    # Add the updated rule
    if [ -n "$new_cidr" ]; then
        echo "    ip saddr $new_cidr $new_proto dport $new_port $nft_action" >> "$TMPFILE"
    else
        echo "    $new_proto dport $new_port $nft_action" >> "$TMPFILE"
    fi

    # Close the ruleset
    cat >> "$TMPFILE" << 'EOF'
  }
}
EOF

    # Apply atomically
    if ! nft -f "$TMPFILE" 2>&1; then
        # Rollback on failure
        if [ -f "$backup_file" ]; then
            nft -f "$backup_file" 2>/dev/null || true
        fi
        die ERR_OPERATION_FAILED "Failed to edit firewall rule"
    fi

    rm -f "$backup_file"
    log_event "Firewall rule edited (old: port=$old_port proto=$old_proto, new: port=$new_port proto=$new_proto)"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Rule updated successfully",
            old: {port: '"$old_port"', proto: "'"$old_proto"'"},
            new: {port: '"$new_port"', proto: "'"$new_proto"'", action: "'"$new_action"'"}
        }'
}

# Feature: --delete-rule with base64 support and actual nftables modification
delete_rule() {
    local rule_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rule_json=$(echo "${2}" | base64 -d)
    else
        rule_json=$(cat)
    fi
    
    echo "$rule_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate rule structure
    jq -e '
        if (.port | type) != "number" or .port < 1 or .port > 65535
            then error("Port out of range") else . end |
        if .proto != "tcp" and .proto != "udp"
            then error("proto must be tcp or udp") else . end
    ' <<< "$rule_json" >/dev/null 2>&1 \
        || die ERR_INVALID_RULE "Rule validation failed"

    local port=$(jq -r '.port' <<< "$rule_json")
    local proto=$(jq -r '.proto' <<< "$rule_json")

    # Get current rules and backup
    local backup_file="/tmp/rise-firewall-backup-$(date +%s)"
    nft -j list table inet rise_filter > "$backup_file" 2>/dev/null || true

    # Build new ruleset without the deleted rule
    cat > "$TMPFILE" << EOF
#!/usr/sbin/nft -f
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

    # Add existing rules (except the one being deleted)
    local existing_rules=$(nft -j list chain inet rise_filter input 2>/dev/null | jq -r '.nftables[]? | select(.rule?) | .rule' 2>/dev/null || echo "")
    
    if [ -n "$existing_rules" ]; then
        echo "$existing_rules" | while IFS= read -r existing_rule; do
            local existing_port=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.right // empty' 2>/dev/null)
            local existing_proto=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | .match.left.payload.protocol // empty' 2>/dev/null)
            
            # Skip if this is the rule being deleted
            if [ "$existing_port" = "$port" ] && [ "$existing_proto" = "$proto" ]; then
                continue
            fi
            
            # Reconstruct the nft rule
            local existing_action=$(echo "$existing_rule" | jq -r '.expr[]? | select(.accept? or .drop?) | if .accept then "accept" elif .drop then "drop" else "" end' 2>/dev/null)
            local existing_cidr=$(echo "$existing_rule" | jq -r '.expr[]? | select(.match?) | select(.match.left.payload.type == "ipv4_address") | .match.right // empty' 2>/dev/null)
            
            if [ -n "$existing_cidr" ]; then
                echo "    ip saddr $existing_cidr $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            else
                echo "    $existing_proto dport $existing_port $existing_action" >> "$TMPFILE"
            fi
        done
    fi

    # Close the ruleset
    cat >> "$TMPFILE" << 'EOF'
  }
}
EOF

    # Apply atomically
    if ! nft -f "$TMPFILE" 2>&1; then
        # Rollback on failure
        if [ -f "$backup_file" ]; then
            nft -f "$backup_file" 2>/dev/null || true
        fi
        die ERR_OPERATION_FAILED "Failed to delete firewall rule"
    fi

    rm -f "$backup_file"
    log_event "Firewall rule deleted (port: $port, proto: $proto)"

    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Rule deleted successfully",
            port: '"$port"',
            proto: "'"$proto"'"
        }'
}

# Main entry point
case "${1:-}" in
    --scan)
        scan_ports
        ;;
    --apply)
        apply_rules "$@"
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
    --list-rules)
        list_rules
        ;;
    --add-rule)
        add_rule "$@"
        ;;
    --edit-rule)
        edit_rule "$@"
        ;;
    --delete-rule)
        delete_rule "$@"
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--scan|--apply|--confirm|--rollback|--flush|--list-rules|--add-rule|--edit-rule|--delete-rule|--version}"
        ;;
esac
