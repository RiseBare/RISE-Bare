#!/usr/bin/env bats

# Unit tests for rise-docker.sh

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-docker.sh"
}

@test "docker: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.api_version == "1.0"' > /dev/null
    echo "$output" | jq -e '.script_version == "1.0.0"' > /dev/null
}

@test "docker: no args returns usage error" {
    run bash "$SCRIPT" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "docker: --status returns valid JSON" {
    run bash "$SCRIPT" --status
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
}

@test "docker: --list returns valid JSON" {
    run bash "$SCRIPT" --list
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
}

@test "docker: --start without container ID returns error" {
    run bash "$SCRIPT" --start
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "docker: --stop without container ID returns error" {
    run bash "$SCRIPT" --stop
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "docker: --restart without container ID returns error" {
    run bash "$SCRIPT" --restart
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "docker: --start with invalid container ID format returns error" {
    run bash "$SCRIPT" --start "invalid container id!"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_INPUT"' > /dev/null
}
