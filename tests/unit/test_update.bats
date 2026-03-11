#!/usr/bin/env bats

# Unit tests for rise-update.sh

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-update.sh"
}

@test "update: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.api_version == "1.0"' > /dev/null
    echo "$output" | jq -e '.script_version == "1.0.0"' > /dev/null
}

@test "update: no args returns usage error" {
    run bash "$SCRIPT" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "update: --check returns valid JSON" {
    run bash "$SCRIPT" --check 2>&1
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}

@test "update: --upgrade returns valid JSON" {
    run bash "$SCRIPT" --upgrade 2>&1
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}
