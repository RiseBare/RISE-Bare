#!/usr/bin/env bats

# Unit tests for rise-onboard.sh

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-onboard.sh"
}

@test "onboard: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.api_version == "1.0"' > /dev/null
    echo "$output" | jq -e '.script_version == "1.0.0"' > /dev/null
}

@test "onboard: no args returns usage error" {
    run bash "$SCRIPT" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "onboard: --check returns valid JSON" {
    run bash "$SCRIPT" --check
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.rise_installed != null' > /dev/null
    echo "$output" | jq -e '.rise_admin_exists != null' > /dev/null
    echo "$output" | jq -e '.ssh_key_installed != null' > /dev/null
}

@test "onboard: --list-devices returns valid JSON" {
    run bash "$SCRIPT" --list-devices
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}

@test "onboard: --add-device without key returns error" {
    run bash "$SCRIPT" --add-device
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "onboard: --remove-device without key returns error" {
    run bash "$SCRIPT" --remove-device
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "onboard: --finalize without key returns error" {
    run bash "$SCRIPT" --finalize
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "onboard: --add-device with invalid key format returns error" {
    run bash "$SCRIPT" --add-device "invalid key format"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_PUBKEY"' > /dev/null
}

@test "onboard: --finalize with invalid key format returns error" {
    run bash "$SCRIPT" --finalize "invalid key format"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_PUBKEY"' > /dev/null
}
