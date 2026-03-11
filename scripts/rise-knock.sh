#!/bin/bash
# Script: rise-knock.sh
# Version: 1.0.0
# Description: RISE Knock Knock Port Knocking Management
#              Uses NFTables for modern Linux firewall (same as rise-firewall.sh)

set -Eeuo pipefail

# API version (major.minor) - must match client expectation
readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

# Knock configuration directories
readonly KNOCK_DIR="/etc/knock"
readonly KNOCK_SEQUENCE_FILE="$KNOCK_DIR/sequence"
readonly KNOCK_CONFIG_DIR="/var/lib/rise"

# Locale enforcement (prevent localized command output)
export LANG=C
export LC_ALL=C

# flock on FD 201 (different from firewall's FD 200)
exec 201>/var/lock/rise-knock.lock
flock -n 201 || {
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg code "ERR_LOCKED" \
        --arg message "Another RISE operation in progress" \
        --arg exit_code "4" \
        '{status: "error", api_version: $api_version, code: $code, message: $message, exit_code: ($exit_code | tonumber)}'
    exit 4
}

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

# Dependency checks
for cmd in jq nft apt-get systemctl; do
    command -v "$cmd" >/dev/null 2>&1 || die ERR_DEPENDENCY "$cmd not installed" 2
done

# Initialize directories
init_directories() {
    mkdir -p "$KNOCK_DIR"
    chmod 700 "$KNOCK_DIR"
    mkdir -p "$KNOCK_CONFIG_DIR"
}

# Generate random port sequence
generate_sequence() {
    local count="${1:-3}"
    local sequence=""
    
    for i in $(seq 1 "$count"); do
        PORT=$((1024 + RANDOM % 64512))  # 1024-65535 range
        sequence="$sequence$PORT"
        [ $i -lt $count ] && sequence="$sequence,"
    done
    
    echo "$sequence"
}

# Configure NFTables for port knocking
configure_nftables_ruleset() {
    local open_sequence="$1"
    local close_sequence="$2"
    
    cat > "$KNOCK_DIR/knockd.conf" << EOF
[options]
        UseSyslog

[openSSH]
        sequence = [$open_sequence]
        seq_timeout = 10
        command = /usr/local/bin/rise-knock-open.sh %IP%
        tcpflags = syn

[closeSSH]
        sequence = [$close_sequence]
        seq_timeout = 10
        command = /usr/local/bin/rise-knock-close.sh %IP%
        tcpflags = syn
EOF
}

# Create NFTables scripts
create_scripts() {
    # Open script - adds NFTables rule
    cat > /usr/local/bin/rise-knock-open.sh << 'EOF'
#!/bin/bash
IP=$1
# Log the event
echo "$(date): Port knocking - granting SSH access to $IP" >> /var/log/knock.log
# Add NFTables rule for the source IP
nft add rule inet rise_filter input ip saddr $IP tcp dport 22 accept
EOF

    # Close script - removes NFTables rule  
    cat > /usr/local/bin/rise-knock-close.sh << 'EOF'
#!/bin/bash
IP=$1
# Log the event
echo "$(date): Port knocking - revoking SSH access from $IP" >> /var/log/knock.log
# Remove NFTables rule for the source IP
nft delete rule inet rise_filter input ip saddr $IP tcp dport 22 accept
done
EOF

    chmod +x /usr/local/bin/rise-knock-*.sh
}

# Install knockd service
install_knockd() {
    echo "Installing knockd package..."
    apt-get update && apt-get install -y knockd || die ERR_INSTALL_FAILED "Failed to install knockd"
    
    echo "Creating configuration..."
    init_directories
    
    # Generate sequences
    local open_seq=$(generate_sequence 3)
    local close_seq=$(generate_sequence 3)
    
    configure_nftables_ruleset "$open_seq" "$close_seq"
    create_scripts
    chmod 600 "$KNOCK_DIR/knockd.conf"
    
    # Configure service to start automatically
    systemctl enable knockd
    systemctl start knockd
    
    # Store sequence info for client retrieval
    jq -n \
        --arg open_sequence "$open_seq" \
        --arg close_sequence "$close_seq" \
        '{open_sequence: $open_sequence, close_sequence: $close_sequence}' > "$KNOCK_CONFIG_DIR/knock-info.json"
    
    # Return success with sequence info
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg open_sequence "$open_seq" \
        --arg close_sequence "$close_seq" \
        '{status: "success", api_version: $api_version, open_sequence: $open_sequence, close_sequence: $close_sequence}'
}

# Uninstall knockd
uninstall_knockd() {
    echo "Stopping knockd service..."
    systemctl stop knockd 2>/dev/null || true
    systemctl disable knockd 2>/dev/null || true
    
    echo "Removing knockd package..."
    apt-get remove -y knockd || true
    
    echo "Cleaning up configuration..."
    rm -rf "$KNOCK_DIR"
    rm -f /usr/local/bin/rise-knock-*.sh
    rm -f "$KNOCK_CONFIG_DIR/knock-info.json"
    
    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, message: "Knockd uninstalled"}'
}

# Generate new sequence
generate_sequence_cmd() {
    if [ ! -f "$KNOCK_DIR/knockd.conf" ]; then
        die ERR_NOT_CONFIGURED "Knockd not configured" 3
    fi
    
    # Generate sequences
    local open_seq=$(generate_sequence 3)
    local close_seq=$(generate_sequence 3)
    
    configure_nftables_ruleset "$open_seq" "$close_seq"
    
    # Restart service
    systemctl restart knockd
    
    # Store sequence info
    jq -n \
        --arg open_sequence "$open_seq" \
        --arg close_sequence "$close_seq" \
        '{open_sequence: $open_sequence, close_sequence: $close_sequence}' > "$KNOCK_CONFIG_DIR/knock-info.json"
    
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg open_sequence "$open_seq" \
        --arg close_sequence "$close_seq" \
        '{status: "success", api_version: $api_version, open_sequence: $open_sequence, close_sequence: $close_sequence}'
}

# Get current sequence
get_sequence() {
    if [ ! -f "$KNOCK_CONFIG_DIR/knock-info.json" ]; then
        die ERR_NOT_CONFIGURED "No knock configuration found" 3
    fi
    
    local open_seq=$(jq -r '.open_sequence' "$KNOCK_CONFIG_DIR/knock-info.json")
    local close_seq=$(jq -r '.close_sequence' "$KNOCK_CONFIG_DIR/knock-info.json")
    
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg open_sequence "$open_seq" \
        --arg close_sequence "$close_seq" \
        '{status: "success", api_version: $api_version, open_sequence: $open_sequence, close_sequence: $close_sequence}'
}

# Get service status
get_status() {
    if systemctl is-active knockd >/dev/null 2>&1; then
        STATUS="active"
    else
        STATUS="inactive"
    fi
    
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg status "$STATUS" \
        '{status: "success", api_version: $api_version, service_status: $status}'
}

# Export configuration
export_config() {
    if [ ! -f "$KNOCK_CONFIG_DIR/knock-info.json" ]; then
        die ERR_NOT_CONFIGURED "No knock configuration to export" 3
    fi
    
    local config_content=$(cat "$KNOCK_CONFIG_DIR/knock-info.json")
    
    jq -n \
        --arg api_version "$API_VERSION" \
        --argjson config "$config_content" \
        '{status: "success", api_version: $api_version, config: $config}'
}

# Import configuration
import_config() {
    local config_json=""
    
    if [ "${2:-}" = "--base64" ] && [ -n "${3:-}" ]; then
        config_json=$(echo "${3}" | base64 -d)
    else
        config_json=$(cat)
    fi
    
    echo "$config_json" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"
    
    local open_seq=$(echo "$config_json" | jq -r '.open_sequence')
    local close_seq=$(echo "$config_json" | jq -r '.close_sequence')
    
    configure_nftables_ruleset "$open_seq" "$close_seq"
    systemctl restart knockd
    
    # Store configuration
    echo "$config_json" > "$KNOCK_CONFIG_DIR/knock-info.json"
    
    jq -n \
        --arg api_version "$API_VERSION" \
        '{status: "success", api_version: $api_version, message: "Configuration imported successfully"}'
}

# Main entry point
case "${1:-}" in
    --install)
        install_knockd
        ;;
    
    --uninstall)
        uninstall_knockd
        ;;
    
    --generate-sequence)
        generate_sequence_cmd
        ;;
    
    --get-sequence)
        get_sequence
        ;;
    
    --status)
        get_status
        ;;
    
    --export)
        export_config
        ;;
    
    --import)
        import_config "$@"
        ;;
    
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--install|--uninstall|--generate-sequence|--get-sequence|--status|--export|--import|--version}"
        ;;
esac