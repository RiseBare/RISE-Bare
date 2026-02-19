#!/usr/bin/env bats

# Integration tests for health check

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../scripts"

@test "health: --version returns valid JSON" {
    run bash "$SCRIPT_DIR/rise-health.sh" --version
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "health: returns valid JSON" {
    run bash "$SCRIPT_DIR/rise-health.sh"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "health: returns all check fields" {
    run bash "$SCRIPT_DIR/rise-health.sh"
    run bash -c "echo '$output' | jq -e '.checks.sudoers_file'"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.checks.ssh_dropin_clean'"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.checks.nftables_include'"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.checks.scripts_present'"
    [ "$status" -eq 0 ]
}

@test "health: check values are pass or fail" {
    run bash "$SCRIPT_DIR/rise-health.sh"
    run bash -c "echo '$output' | jq -r '.checks.sudoers_file' | grep -E '^(pass|fail)$'"
    [ "$status" -eq 0 ]
}
