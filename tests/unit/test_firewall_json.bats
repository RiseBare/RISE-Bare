#!/usr/bin/env bats

# Unit tests for rise-firewall.sh - JSON output validation

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-firewall.sh"
}

@test "JSON output: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    run echo "$output" | jq -e '.status == "success"'
    [ "$?" -eq 0 ]
}

@test "JSON output: --version has api_version" {
    run bash "$SCRIPT" --version
    run echo "$output" | jq -e '.api_version == "1.0"'
    [ "$status" -eq 0 ]
}

@test "JSON output: error has code field" {
    run bash "$SCRIPT" --invalid-flag
    run echo "$output" | jq -e '.code != null'
    [ "$status" -eq 0 ]
}

@test "JSON output: error has message field" {
    run bash "$SCRIPT" --invalid-flag
    run echo "$output" | jq -e '.message != null'
    [ "$status" -eq 0 ]
}
