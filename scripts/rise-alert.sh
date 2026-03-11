#!/bin/bash
# Script: rise-alert.sh
# Version: 1.0.0
# Description: RISE Email Alert Management - SMTP configuration and email sending
#              Supports validation codes, test emails, and SMTP configuration

set -Eeuo pipefail

# API version (major.minor)
readonly API_VERSION="1.0"
readonly SCRIPT_VERSION="1.0.0"

# Configuration directories
readonly CONFIG_DIR="/etc/rise"
readonly VALIDATION_DIR="/etc/rise/validation"
readonly VALIDATION_CODE_FILE="$VALIDATION_DIR/validation.code"
readonly SMTP_CONF_FILE="$CONFIG_DIR/smtp.conf"

# Validation code expiry time (15 minutes in seconds)
readonly VALIDATION_EXPIRY=900

# Locale enforcement (prevent localized command output)
export LANG=C
export LC_ALL=C

# flock on FD 200 (convention: use 200-209 for custom file descriptors)
# Prevents concurrent RISE operations
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

# Temporary file for atomic operations
TMPFILE=$(mktemp /tmp/rise-alert-XXXXXX)

# Cleanup handler
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
for cmd in jq curl; do
    command -v "$cmd" >/dev/null 2>&1 || die ERR_DEPENDENCY "$cmd not installed" 2
done

# Initialize configuration directory
init_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        chmod 700 "$CONFIG_DIR"
    fi
}

# Initialize validation directory
init_validation_dir() {
    if [ ! -d "$VALIDATION_DIR" ]; then
        mkdir -p "$VALIDATION_DIR"
        chmod 700 "$VALIDATION_DIR"
    fi
}

# Check if SMTP is configured
is_smtp_configured() {
    if [ ! -f "$SMTP_CONF_FILE" ]; then
        return 1
    fi
    
    # Check if credentials are active
    local active
    active=$(jq -r '.active // false' "$SMTP_CONF_FILE" 2>/dev/null)
    [ "$active" = "true" ]
}

# Check if validation is complete
is_validated() {
    if [ ! -f "$VALIDATION_CODE_FILE" ]; then
        return 1
    fi
    
    # Check if code is still valid
    local timestamp
    timestamp=$(jq -r '.timestamp // 0' "$VALIDATION_CODE_FILE" 2>/dev/null)
    local current_time
    current_time=$(date +%s)
    local age=$((current_time - timestamp))
    
    if [ "$age" -gt "$VALIDATION_EXPIRY" ]; then
        rm -f "$VALIDATION_CODE_FILE"
        return 1
    fi
    
    return 0
}

# Generate 6-digit validation code
generate_validation_code() {
    shuf -i 100000-999999 -n 1
}

# Store SMTP credentials (base64 encoded JSON)
store_smtp_credentials() {
    local json_data="$1"
    
    init_config_dir
    
    # Encode as base64
    local encoded
    encoded=$(echo -n "$json_data" | base64 -w 0)
    
    # Store with metadata
    jq -n \
        --arg encoded "$encoded" \
        --arg timestamp "$(date +%s)" \
        --arg active "false" \
        '{
            encoded: $encoded,
            timestamp: ($timestamp | tonumber),
            active: ($active == "true")
        }' > "$SMTP_CONF_FILE"
    
    chmod 600 "$SMTP_CONF_FILE"
    log_event "SMTP credentials stored"
}

# Decode and get SMTP credentials
get_smtp_credentials() {
    if [ ! -f "$SMTP_CONF_FILE" ]; then
        return 1
    fi
    
    local encoded
    encoded=$(jq -r '.encoded // empty' "$SMTP_CONF_FILE")
    
    if [ -z "$encoded" ]; then
        return 1
    fi
    
    echo "$encoded" | base64 -d
}

# Send email via SMTP using curl
send_email() {
    local smtp_url="$1"
    local smtp_port="$2"
    local username="$3"
    local password="$4"
    local from_email="$5"
    local to_email="$6"
    local subject="$7"
    local body="$8"
    local use_tls="${9:-true}"
    
    # Build the email content
    local boundary="boundary_$(date +%s)_$$"
    local email_content=""
    
    email_content="--$boundary\r\n"
    email_content+="Content-Type: text/plain; charset=UTF-8\r\n"
    email_content+="Content-Transfer-Encoding: quoted-printable\r\n"
    email_content+="\r\n"
    email_content+="$body\r\n"
    email_content+="\r\n"
    email_content+="--$boundary--\r\n"
    
    # Encode content for base64
    local encoded_content
    encoded_content=$(echo -n "$email_content" | base64 -w 0)
    
    # Build the full email
    local full_email=""
    full_email+="From: $from_email\r\n"
    full_email+="To: $to_email\r\n"
    full_email+="Subject: $subject\r\n"
    full_email+="MIME-Version: 1.0\r\n"
    full_email+="Content-Type: multipart/alternative; boundary=\"$boundary\"\r\n"
    full_email+="\r\n"
    full_email+="$encoded_content"
    
    # Encode full email for base64
    local encoded_email
    encoded_email=$(echo -n "$full_email" | base64 -w 0)
    
    # Build SMTP URL
    local smtp_proto="smtp"
    if [ "$use_tls" = "true" ]; then
        smtp_proto="smtps"
    fi
    
    local smtp_server="${smtp_proto}://${smtp_url}:${smtp_port}"
    
    # Send email using curl
    local response
    response=$(curl -s -S --url "$smtp_server" \
        --mail-from "$from_email" \
        --mail-rcpt "$to_email" \
        --upload-file - \
        --user "$username:$password" \
        --ssl-reqd 2>&1)
    
    local curl_exit=$?
    
    if [ $curl_exit -ne 0 ]; then
        die ERR_EMAIL_FAILED "Failed to send email: curl exit code $curl_exit"
    fi
    
    if [[ "$response" =~ ^5 ]]; then
        die ERR_EMAIL_FAILED "SMTP server error: $response"
    fi
    
    log_event "Email sent successfully to $to_email"
    return 0
}

# Feature: --configure
configure_smtp() {
    local json_data=""
    
    # Handle base64 encoded input
    if [ "${1:-}" = "--base64" ] && [ -n "${2:-}" ]; then
        json_data=$(echo "${2}" | base64 -d)
    else
        json_data=$(cat)
    fi
    
    echo "$json_data" | jq -e . >/dev/null 2>&1 || die ERR_INVALID_INPUT "Malformed JSON payload"
    
    # Validate required fields
    local required_fields=("smtp_url" "smtp_port" "username" "password" "from_email" "destination_email")
    for field in "${required_fields[@]}"; do
        local value
        value=$(jq -r ".$field // empty" <<< "$json_data")
        if [ -z "$value" ]; then
            die ERR_INVALID_INPUT "Missing required field: $field"
        fi
    done
    
    # Store credentials
    store_smtp_credentials "$json_data"
    
    # Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "SMTP credentials stored successfully"
        }'
}

# Feature: --send-validation
send_validation() {
    local email="${1:-}"
    
    if [ -z "$email" ]; then
        die ERR_INVALID_INPUT "Email address required"
    fi
    
    # Validate email format
    if ! [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        die ERR_INVALID_INPUT "Invalid email format: $email"
    fi
    
    # Check if SMTP is configured
    if ! is_smtp_configured; then
        die ERR_NOT_CONFIGURED "SMTP not configured. Please configure first with --configure"
    fi
    
    # Get SMTP credentials
    local credentials
    credentials=$(get_smtp_credentials)
    
    local smtp_url
    smtp_url=$(echo "$credentials" | jq -r '.smtp_url')
    local smtp_port
    smtp_port=$(echo "$credentials" | jq -r '.smtp_port')
    local username
    username=$(echo "$credentials" | jq -r '.username')
    local password
    password=$(echo "$credentials" | jq -r '.password')
    local from_email
    from_email=$(echo "$credentials" | jq -r '.from_email')
    local use_tls
    use_tls=$(echo "$credentials" | jq -r '.use_tls // true')
    
    # Generate validation code
    local code
    code=$(generate_validation_code)
    local timestamp
    timestamp=$(date +%s)
    
    # Store code with timestamp
    init_validation_dir
    jq -n \
        --arg code "$code" \
        --argjson timestamp "$timestamp" \
        '{
            code: $code,
            timestamp: $timestamp
        }' > "$VALIDATION_CODE_FILE"
    
    chmod 600 "$VALIDATION_CODE_FILE"
    
    # Send validation email
    local subject="RISE-Bare: Your Validation Code"
    local body="Your validation code is: $code\n\nThis code will expire in 15 minutes."
    
    if ! send_email "$smtp_url" "$smtp_port" "$username" "$password" "$from_email" "$email" "$subject" "$body" "$use_tls"; then
        die ERR_EMAIL_FAILED "Failed to send validation email"
    fi
    
    # Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Validation code sent to $email"
        }'
}

# Feature: --verify-code
verify_code() {
    local code="${1:-}"
    
    if [ -z "$code" ]; then
        die ERR_INVALID_INPUT "Validation code required"
    fi
    
    # Check if validation code file exists
    if [ ! -f "$VALIDATION_CODE_FILE" ]; then
        die ERR_NOT_FOUND "No validation code found. Please request one with --send-validation"
    fi
    
    # Get stored code and timestamp
    local stored_code
    stored_code=$(jq -r '.code // empty' "$VALIDATION_CODE_FILE")
    local timestamp
    timestamp=$(jq -r '.timestamp // 0' "$VALIDATION_CODE_FILE")
    local current_time
    current_time=$(date +%s)
    local age=$((current_time - timestamp))
    
    # Check if code matches
    if [ "$code" != "$stored_code" ]; then
        die ERR_INVALID_CODE "Invalid validation code"
    fi
    
    # Check if code has expired
    if [ "$age" -gt "$VALIDATION_EXPIRY" ]; then
        rm -f "$VALIDATION_CODE_FILE"
        die ERR_CODE_EXPIRED "Validation code has expired. Please request a new one"
    fi
    
    # Mark credentials as active
    if [ -f "$SMTP_CONF_FILE" ]; then
        local temp_file=$(mktemp)
        jq '.active = true' "$SMTP_CONF_FILE" > "$temp_file"
        mv "$temp_file" "$SMTP_CONF_FILE"
        chmod 600 "$SMTP_CONF_FILE"
    fi
    
    # Remove validation code
    rm -f "$VALIDATION_CODE_FILE"
    
    # Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Validation successful. Credentials are now active."
        }'
}

# Feature: --status
get_status() {
    local configured="false"
    local validated="false"
    local smtp_configured="false"
    
    # Check if SMTP is configured
    if is_smtp_configured; then
        configured="true"
        smtp_configured="true"
    fi
    
    # Check if validated
    if is_validated; then
        validated="true"
    fi
    
    # Return status as JSON
    jq -n \
        --arg configured "$configured" \
        --arg validated "$validated" \
        --arg smtp_configured "$smtp_configured" \
        '{
            configured: ($configured == "true"),
            validated: ($validated == "true"),
            smtpConfigured: ($smtp_configured == "true")
        }'
}

# Feature: --test
send_test_email() {
    # Check if SMTP is configured
    if ! is_smtp_configured; then
        die ERR_NOT_CONFIGURED "SMTP not configured. Please configure first with --configure"
    fi
    
    # Get SMTP credentials
    local credentials
    credentials=$(get_smtp_credentials)
    
    local smtp_url
    smtp_url=$(echo "$credentials" | jq -r '.smtp_url')
    local smtp_port
    smtp_port=$(echo "$credentials" | jq -r '.smtp_port')
    local username
    username=$(echo "$credentials" | jq -r '.username')
    local password
    password=$(echo "$credentials" | jq -r '.password')
    local from_email
    from_email=$(echo "$credentials" | jq -r '.from_email')
    local destination_email
    destination_email=$(echo "$credentials" | jq -r '.destination_email // $from_email')
    local use_tls
    use_tls=$(echo "$credentials" | jq -r '.use_tls // true')
    
    # Send test email
    local subject="RISE-Bare: Test Email"
    local body="This is a test email from RISE-Bare.\n\nIf you received this, your email configuration is working correctly!"
    
    if ! send_email "$smtp_url" "$smtp_port" "$username" "$password" "$from_email" "$destination_email" "$subject" "$body" "$use_tls"; then
        die ERR_EMAIL_FAILED "Failed to send test email"
    fi
    
    # Return success
    jq -n \
        --arg api_version "$API_VERSION" \
        '{
            status: "success",
            api_version: $api_version,
            message: "Test email sent successfully"
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

# Main entry point
case "${1:-}" in
    --configure)
        configure_smtp "$@"
        ;;
    --send-validation)
        send_validation "${2:-}"
        ;;
    --verify-code)
        verify_code "${2:-}"
        ;;
    --status)
        get_status
        ;;
    --test)
        send_test_email
        ;;
    --version)
        jq -n \
            --arg api_version "$API_VERSION" \
            --arg script_version "$SCRIPT_VERSION" \
            '{status: "success", api_version: $api_version, script_version: $script_version}'
        ;;
    *)
        die ERR_INVALID_ARGUMENTS "Usage: $0 {--configure|--send-validation <email>|--verify-code <code>|--status|--test|--version}"
        ;;
esac
