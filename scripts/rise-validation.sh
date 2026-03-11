#!/bin/bash
# Script: rise-validation.sh
# Version: 1.0.0
# Description: Shared validation functions for RISE scripts

set -Eeuo pipefail

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

# Validate SSH public key format
validate_ssh_key() {
    local key="$1"
    
    # Check general format: <type> <base64> [optional comment]
    if [[ ! "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]{50,}([[:space:]].*)?$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid SSH public key format (must be ssh-ed25519, ssh-rsa, or ecdsa-sha2-nistp*)\"}"
        return 1
    fi
    
    # Use ssh-keygen to validate format if available
    if command -v ssh-keygen >/dev/null 2>&1; then
        if ! echo "$key" | ssh-keygen -l -f /dev/stdin >/dev/null 2>&1; then
            echo "{\"status\": \"error\", \"message\": \"Invalid SSH public key (ssh-keygen validation failed)\"}"
            return 1
        fi
    fi
    
    return 0
}

# Validate username (alphanumeric + underscore, 1-32 chars)
validate_username() {
    local username="$1"
    
    # Check length
    if [ ${#username} -lt 1 ] || [ ${#username} -gt 32 ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid username: $username (must be 1-32 characters)\"}"
        return 1
    fi
    
    # Check allowed characters (alphanumeric + underscore)
    if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid username: $username (must be alphanumeric + underscore only)\"}"
        return 1
    fi
    
    # Check it doesn't start with a number (common convention)
    if [[ "$username" =~ ^[0-9] ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid username: $username (cannot start with a number)\"}"
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

# Validate package name (APT format)
validate_package_name() {
    local pkg_name="$1"
    
    # APT package names: lowercase alphanumeric, +, -, ., _
    if [[ ! "$pkg_name" =~ ^[a-z0-9][a-z0-9+.\-_]*$ ]]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid package name: $pkg_name\"}"
        return 1
    fi
    
    # Check length
    if [ ${#pkg_name} -gt 128 ]; then
        echo "{\"status\": \"error\", \"message\": \"Invalid package name: $pkg_name (too long)\"}"
        return 1
    fi
    
    return 0
}

# Validate JSON input
validate_json() {
    local json="$1"
    
    if ! echo "$json" | jq empty 2>/dev/null; then
        echo "{\"status\": \"error\", \"message\": \"Invalid JSON input\"}"
        return 1
    fi
    
    return 0
}

# Validate base64 input
validate_base64() {
    local data="$1"
    
    if ! echo "$data" | base64 -d >/dev/null 2>&1; then
        echo "{\"status\": \"error\", \"message\": \"Invalid base64 input\"}"
        return 1
    fi
    
    return 0
}
