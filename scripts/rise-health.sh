#!/usr/bin/env bash
# rise-health.sh - RISE Health Check Script
# Version: 1.1.0
# Description: Server health monitoring without root privileges
#              Optimized: parallelized checks and system info caching

readonly API_VERSION="1.1"
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME="$(basename "$0")"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Cache configuration
readonly CACHE_DIR="/var/lib/rise"
readonly SYSTEM_INFO_CACHE="$CACHE_DIR/system_info_cache.json"
readonly SYSTEM_INFO_CACHE_TTL=10  # Short TTL for system info

# Verify jq is installed BEFORE first use
if ! command -v jq >/dev/null 2>&1; then
    printf '{"status":"error","api_version":"%s","code":"ERR_DEPENDENCY","message":"jq not installed"}\n' \
        "${API_VERSION}"
    exit 2
fi

# Initialize cache directory
init_cache_dir() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
        chmod 700 "$CACHE_DIR"
    fi
}

# Check if system info cache is valid
is_system_info_cache_valid() {
    if [ ! -f "$SYSTEM_INFO_CACHE" ]; then
        return 1
    fi
    
    local cache_age=$(($(date +%s) - $(stat -c %Y "$SYSTEM_INFO_CACHE" 2>/dev/null || echo "0")))
    if [ "$cache_age" -gt "$SYSTEM_INFO_CACHE_TTL" ]; then
        return 1
    fi
    
    return 0
}

# Refresh system info cache
refresh_system_info_cache() {
    init_cache_dir
    
    # Gather system info in parallel where possible
    local os_info kernel_info memory_info disk_info
    
    # Parallelize independent checks
    {
        os_info=$(cat /etc/os-release 2>/dev/null | jq -Rs '{os_release: .}' || echo '{"os_release": ""}')
    } &
    
    {
        kernel_info=$(jq -n \
            --arg kernel "$(uname -r)" \
            --arg arch "$(uname -m)" \
            '{kernel: $kernel, architecture: $arch}')
    } &
    
    {
        memory_info=$(free -b 2>/dev/null | awk 'NR==2{printf "{\"total\":%d,\"used\":%d,\"free\":%d,\"available\":%d}', $2, $3, $4, $7; echo '}')
    } &
    
    {
        disk_info=$(df -B1 / 2>/dev/null | awk 'NR==2{printf "{\"total\":%d,\"used\":%d,\"free\":%d,\"usage\":%d}', $2, $3, $4, $5; echo '}')
    } &
    
    # Wait for all background jobs
    wait
    
    # Collect results
    os_info=$(cat /etc/os-release 2>/dev/null | jq -Rs '{os_release: .}' || echo '{"os_release": ""}')
    kernel_info=$(jq -n \
        --arg kernel "$(uname -r)" \
        --arg arch "$(uname -m)" \
        '{kernel: $kernel, architecture: $arch}')
    memory_info=$(free -b 2>/dev/null | awk 'NR==2{printf "{\"total\":%d,\"used\":%d,\"free\":%d,\"available\":%d}', $2, $3, $4, $7; echo '}')
    disk_info=$(df -B1 / 2>/dev/null | awk 'NR==2{printf "{\"total\":%d,\"used\":%d,\"free\":%d,\"usage\":%d}', $2, $3, $4, $5; echo '}')
    
    # Write cache with metadata
    jq -n \
        --argjson os_info "$os_info" \
        --argjson kernel_info "$kernel_info" \
        --argjson memory_info "$memory_info" \
        --argjson disk_info "$disk_info" \
        --argjson timestamp "$(date +%s)" \
        --arg ttl "$SYSTEM_INFO_CACHE_TTL" \
        '{
            os_info: $os_info,
            kernel_info: $kernel_info,
            memory_info: $memory_info,
            disk_info: $disk_info,
            timestamp: $timestamp,
            ttl: $ttl,
            valid: true
        }' > "$SYSTEM_INFO_CACHE"
    
    chmod 600 "$SYSTEM_INFO_CACHE"
}

# Get cached system info if valid
get_cached_system_info() {
    if is_system_info_cache_valid; then
        cat "$SYSTEM_INFO_CACHE"
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
build_health_status() {
    local system_info
    system_info=$(get_cached_system_info)
    
    # Refresh cache if invalid
    if [ -z "$system_info" ]; then
        refresh_system_info_cache
        system_info=$(get_cached_system_info)
    fi
    
    jq -n \
        --arg api_version "$API_VERSION" \
        --arg sudoers_file "$(check_sudoers_file)" \
        --arg ssh_dropin_clean "$(check_ssh_dropin_clean)" \
        --arg nftables_include "$(check_nftables_include)" \
        --arg scripts_present "$(check_scripts_present)" \
        --argjson system_info "$system_info" \
        '{
            status: "success",
            api_version: $api_version,
            checks: {
                sudoers_file: $sudoers_file,
                ssh_dropin_clean: $ssh_dropin_clean,
                nftables_include: $nftables_include,
                scripts_present: $scripts_present
            },
            system_info: $system_info
        }'
}

# Run health checks
build_health_status
