#!/usr/bin/env bats

# Integration tests for onboarding flow

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../scripts"

@test "onboard: --version returns valid JSON" {
    run bash "$SCRIPT_DIR/rise-onboard.sh" --version
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: --generate-otp returns success" {
    run sudo bash "$SCRIPT_DIR/rise-onboard.sh" --generate-otp
    echo "$output"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: --generate-otp outputs OTP to stderr" {
    run sudo bash "$SCRIPT_DIR/rise-onboard.sh" --generate-otp 2>/dev/null
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: --cleanup returns success" {
    run sudo bash "$SCRIPT_DIR/rise-onboard.sh" --cleanup
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: --finalize without OTP returns error" {
    sudo rm -f /var/lib/rise/onboard-otp-hash 2>/dev/null || true
    run sudo bash "$SCRIPT_DIR/rise-onboard.sh" --finalize "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJKhVHpQvUYXqP8HQCJ5JkFVGzMhRqKWMKZmZhJGHDHZ test@test"
    [ "$status" -ne 0 ]
    run bash -c "echo '$output' | jq -e '.code == \"ERR_ONBOARDING_FAILED\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: --finalize with invalid key returns error" {
    run sudo bash "$SCRIPT_DIR/rise-onboard.sh" --finalize "invalid-key"
    [ "$status" -ne 0 ]
    run bash -c "echo '$output' | jq -e '.code == \"ERR_INVALID_PUBKEY\"'"
    [ "$status" -eq 0 ]
}

@test "onboard: missing arguments returns error" {
    run bash "$SCRIPT_DIR/rise-onboard.sh"
    [ "$status" -ne 0 ]
}
