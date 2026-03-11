#!/bin/bash
# Script: rise-firewall.sh
# Version: 2.1.0
# Description: RISE Firewall Management - atomic rule application with automatic rollback
#              Fixed: SSH injection vulnerabilities, implemented actual CRUD operations
#              Added: Rate limiting for firewall operations
#              Optimized: nftables queries with caching and batch mode

set -Eeuo pipefail

# API version (major.minor) - must match client expectation
readonly API_VERSION="2.1"
readonly SCRIPT_VERSION="2.1.0"

# Rate limiting configuration
readonly RATE_LIMIT_APPLY=10        # Max apply calls per hour
readonly RATE_LIMIT_RULES=30        # Max rule operations (add/edit/delete) per hour
readonly RATE_LIMIT_WINDOW=3600     # Time window in seconds (1 hour)

# Rate limit tracking directory
readonly RATE_LIMIT_DIR="/var/lib/rise"
readonly RATE_LIMIT_APPLY_FILE="$RATE_LIMIT_DIR/apply-rate.log"
readonly RATE_LIMIT_RULES_FILE="$RATE_LIMIT_DIR/rules-rate.log"

# Cache configuration
readonly CACHE_DIR="/var/lib/rise"
readonly CACHE_FILE="$CACHE_DIR/firewall_cache.json"
readonly CACHE_TTL=60               # Cache TTL in seconds

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

# Initialize rate limiting directory
init_rate_limit_dir() {
    if [ ! -d "$RATE_LIMIT_DIR" ]; then
        mkdir -p "$RATE_LIMIT_DIR"
        chmod 700 "$RATE_LIMIT_DIR"
    fi
}

# Initialize cache directory
init_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        chmod 700 "$CACHE_DIR"
    fi
}

# Clean old entries from rate limit log (older than RATE_LIMIT_WINDOW)
clean_old_entries() {
    local log_file="$1"
    local current_time=$(date +%s)
    local cutoff=$((current_time - RATE_LIMIT_WINDOW))
    
    if [ -f "$log_file" ]; then
        # Keep only entries within the time window
        local temp_file=$(mktemp)
        while IFS= read -r timestamp; do
            if [ "$timestamp" -gt "$cutoff" ] 2>/dev/null; then
                echo "$timestamp" >> "$temp_file"
            fi
        done < "$log_file"
        mv "$temp_file" "$log_file"
    fi
}

# Check and record rate limit for an operation
# Args: $1 = operation type ("apply" or "rules"), $2 = operation name
check_rate_limit() {
    local op_type="$1"
    local op_name="$2"
    local log_file
    local max_limit
    
    init_rate_limit_dir
    
    if [ "$op_type" = "apply" ]; then
        log_file="$RATE_LIMIT_APPLY_FILE"
        max_limit="$RATE_LIMIT_APPLY"
    else
        log_file="$RATE_LIMIT_RULES_FILE"
        max_limit="$RATE_LIMIT_RULES"
    fi
    
    # Clean old entries
    clean_old_entries "$log_file"
    
    # Count recent operations
    local count=0
    if [ -f "$log_file" ]; then
        count=$(wc -l < "$log_file")
    fi
    
    # Check if limit exceeded
    if [ "$count" -ge "$max_limit" ]; then
        # Calculate wait time based on oldest entry
        local oldest=$(head -n 1 "$log_file" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local wait_time=$((RATE_LIMIT_WINDOW - (current_time - oldest)))
        if [ "$wait_time" -lt 1 ]; then
            wait_time=1
        fi
        
        echo "{\"status\": \"error\", \"message\": \"Rate limit exceeded. Try again in $wait_time seconds.\"}"
        return 1
    fi
    
    # Record this operation
    echo "$(date +%s)" >> "$log_file"
    return 0
}

# Check if cache is valid (not expired)
# Args: $1 = cache file path, $2 = TTL in seconds
is_cache_valid() {
    local cache_file="$1"
    local ttl="$2"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo "0")))
    if [ "$cache_age" -gt "$ttl" ]; then
        return 1
    fi
    
    return 0
}

# Refresh cache for nftables rules
refresh_cache() {
    init_cache_dir
    
    # Get nftables rules as JSON using batch mode
    local nft_output
    local nft_exit
    
    nft_output=$(nft -j -c list chain inet rise_filter input 2>&1)
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
    
    # Write cache with metadata
    jq -n \
        --argjson data "$nft_output" \
        --argjson timestamp "$(date +%s)" \
        --arg ttl "$CACHE_TTL" \
        '{
            data: $data,
            timestamp: $timestamp,
            ttl: $ttl,
            valid: true
        }' > "$CACHE_FILE"
    
    chmod 600 "$CACHE_FILE"
    log_event "Firewall cache refreshed"
}

# Get cached rules if valid
# Returns: cached rules JSON or empty string
get_cached_rules() {
    if is_cache_valid "$CACHE_FILE" "$CACHE_TTL"; then
        cat "$CACHE_FILE" | jq -r '.data'
    else
        echo ""
    fi
}

# Version flag
if [ "${1:-}" = "--version" ]; then
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg script_version "$SCRIPT_VERSION" \
        '{status: "success", api_version: $api_version, script_version: $script_version}'
    exit 0
fi

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

# Validate IPv4 address
validate_ipv4() {
    local ip="$1"
    
    # Must match x.x.x.x pattern
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid IPv4 address: $ip\"}"
        return 1
    fi
    
    # Validate each octet (0-255)
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            echo "{\"status\": \"error\", \"message\": \"Invalid IPv4 address: $ip (octet out of range)\"}"
            return 1
        fi
    done
    
    return 0
}

# Validate IPv6 address (simplified - basic format check)
validate_ipv6() {
    local ip="$1"
    
    # Basic IPv6 pattern (not comprehensive, but catches common cases)
    if [[ ! "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]] && \
       [[ ! "$ip" =~ ^::1$ ]] && \
       [[ ! "$ip" =~ ^::$ ]] && \
       [[ ! "$ip" =~ ^[0-9a-fA-F]*:[0-9a-fA-F]*:[0-9a-fA-F:]*$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid IPv6 address: $ip\"}"
        return 1
    fi
    
    return 0
}

# Validate IP address (IPv4 or IPv6)
validate_ip() {
    local ip="$1"
    
    if [[ "$ip" == *":"* ]]; then
        validate_ipv6 "$ip" || return 1
    else
        validate_ipv4 "$ip" || return 1
    fi
    
    return 0
}

# Validate CIDR notation (IPv4 or IPv6)
validate_cidr() {
    local cidr="$1"
    
    # Check for IPv6 CIDR
    if [[ "$cidr" == *":"* ]]; then
        # IPv6 CIDR format: address/prefix
        if [[ ! "$cidr" =~ ^[0-9a-fA-F:]+/[0-9]{1,3}$ ]]; then
            echo "{\"status\": \"error\", \"message\": \"Invalid IPv6 CIDR: $cidr\"}"
            return 1
        fi
        
        local prefix="${cidr##*/}"
        if [ "$prefix" -gt 128 ]; then
            echo "{\"status\": \"error\", \"message\": \"Invalid IPv6 CIDR prefix: $prefix (must be 0-128)\"}"
            return 1
        fi
        
        return 0
    else
        # IPv4 CIDR format: x.x.x.x/nn
        if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo "{\"status\": \"error\", \"message\": \"Invalid IPv4 CIDR: $cidr\"}"
            return 1
        fi
        
        # Validate each octet (0-255)
        IFS='.' read -r -a octets <<< "${cidr%/*}"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                echo "{\"status\": \"error\", \"message\": \"Invalid IPv4 CIDR: $cidr (octet out of range)\"}"
                return 1
            fi
        done
        
        # Validate prefix length (0-32)
        local prefix="${cidr#*/}"
        if [ "$prefix" -gt 32 ]; then
            echo "{\"status\": \"error\", \"message\": \"Invalid IPv4 CIDR prefix: $prefix (must be 0-32)\"}"
            return 1
        fi
        
        return 0
    fi
}

# Validate protocol (tcp or udp)
validate_protocol() {
    local protocol="$1"
    
    if [[ "$protocol" != "tcp" && "$protocol" != "udp" ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid protocol: $protocol (must be tcp or udp)\"}"
        return 1
    fi
    
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

        # Validate protocol
        local proto_validation=$(validate_protocol "$proto")
        if [ $? -ne 0 ]; then
            continue
        fi

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
        local port_validation=$(validate_port "$port")
        if [ $? -ne 0 ]; then
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
    # Check rate limit before processing
    if ! check_rate_limit "apply" "apply_rules"; then
        exit 1
    fi
    
    local rules_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rules_json=$(echo "${2}" | base64 -d)
    else
        rules_json=$(cat)
    fi
    
    echo "$rules_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate all rules structure with jq
    while IFS= read -r rule; do
        # Validate port
        local port=$(jq -r '.port' <<< "$rule")
        local port_validation=$(validate_port "$port")
        if [ $? -ne 0 ]; then
            die ERR_INVALID_RULE "$port_validation"
        fi

        # Validate protocol
        local proto=$(jq -r '.proto' <<< "$rule")
        local proto_validation=$(validate_protocol "$proto")
        if [ $? -ne 0 ]; then
            die ERR_INVALID_RULE "$proto_validation"
        fi

        # Validate action
        local action=$(jq -r '.action' <<< "$rule")
        if [[ "$action" != "allow" && "$action" != "drop" ]]; then
            die ERR_INVALID_RULE "Invalid action: $action (must be allow or drop)"
        fi

        # Validate CIDR if present
        local cidr=$(jq -r '.cidr // empty' <<< "$rule")
        if [ -n "$cidr" ]; then
            local cidr_validation=$(validate_cidr "$cidr")
            if [ $? -ne 0 ]; then
                die ERR_INVALID_RULE "$cidr_validation"
            fi
        fi
    done < <(jq -c '.[]' <<< "$rules_json")

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

# Feature: --list-rules with caching
list_rules() {
    # Check if cache is valid
    if is_cache_valid "$CACHE_FILE" "$CACHE_TTL"; then
        # Return cached rules
        local cached_data=$(cat "$CACHE_FILE" | jq -r '.data')
        
        # Parse rules from cached data
        local rules_json="[]"
        
        # Extract rules from nft JSON output
        local rules=$(echo "$cached_data" | jq -r '.nftables[]? | select(.rule?) | .rule' 2>/dev/null)
        
        if [ -n "$rules" ]; then
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

        # Output final JSON with cache metadata
        jq -n \
            --arg api_version "$API_VERSION" \
            --argjson data "$rules_json" \
            --arg cached "true" \
            '{status: "success", api_version: $api_version, data: $data, cached: ($cached == "true")}'
    else
        # Cache is invalid, refresh it
        refresh_cache
        
        # Get fresh rules
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
    fi
}

# Feature: --refresh-cache
refresh_cache_cmd() {
    init_cache_dir
    refresh_cache
    echo "{\"status\": \"success\", \"message\": \"Cache refreshed successfully\"}"
}

# Feature: --add-rule with base64 support and actual nftables modification
add_rule() {
    # Check rate limit before processing
    if ! check_rate_limit "rules" "add_rule"; then
        exit 1
    fi
    
    local rule_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rule_json=$(echo "${2}" | base64 -d)
    else
        rule_json=$(cat)
    fi
    
    echo "$rule_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate port
    local port=$(jq -r '.port' <<< "$rule_json")
    local port_validation=$(validate_port "$port")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$port_validation"
    fi

    # Validate protocol
    local proto=$(jq -r '.proto' <<< "$rule_json")
    local proto_validation=$(validate_protocol "$proto")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$proto_validation"
    fi

    # Validate action
    local action=$(jq -r '.action' <<< "$rule_json")
    if [[ "$action" != "allow" && "$action" != "drop" ]]; then
        die ERR_INVALID_RULE "Invalid action: $action (must be allow or drop)"
    fi

    # Validate CIDR if present
    local cidr=$(jq -r '.cidr // empty' <<< "$rule_json")
    if [ -n "$cidr" ]; then
        local cidr_validation=$(validate_cidr "$cidr")
        if [ $? -ne 0 ]; then
            die ERR_INVALID_RULE "$cidr_validation"
        fi
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
    # Check rate limit before processing
    if ! check_rate_limit "rules" "edit_rule"; then
        exit 1
    fi
    
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

    # Validate new port
    local port_validation=$(validate_port "$new_port")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$port_validation"
    fi

    # Validate new protocol
    local proto_validation=$(validate_protocol "$new_proto")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$proto_validation"
    fi

    # Validate new action
    if [[ "$new_action" != "allow" && "$new_action" != "drop" ]]; then
        die ERR_INVALID_RULE "Invalid action: $new_action (must be allow or drop)"
    fi

    # Validate CIDR if present
    if [ -n "$new_cidr" ]; then
        local cidr_validation=$(validate_cidr "$new_cidr")
        if [ $? -ne 0 ]; then
            die ERR_INVALID_RULE "$cidr_validation"
        fi
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
    # Check rate limit before processing
    if ! check_rate_limit "rules" "delete_rule"; then
        exit 1
    fi
    
    local rule_json=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        rule_json=$(echo "${2}" | base64 -d)
    else
        rule_json=$(cat)
    fi
    
    echo "$rule_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"

    # Validate port
    local port=$(jq -r '.port' <<< "$rule_json")
    local port_validation=$(validate_port "$port")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$port_validation"
    fi

    # Validate protocol
    local proto=$(jq -r '.proto' <<< "$rule_json")
    local proto_validation=$(validate_protocol "$proto")
    if [ $? -ne 0 ]; then
        die ERR_INVALID_RULE "$proto_validation"
    fi

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
    --refresh-cache)
        refresh_cache_cmd
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
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--scan|--apply|--confirm|--rollback|--flush|--list-rules|--refresh-cache|--add-rule|--edit-rule|--delete-rule|--version}"
        ;;
esac
