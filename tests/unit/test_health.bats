#!/usr/bin/env bats

# Unit tests for rise-health.sh

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-health.sh"
}

@test "health: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.api_version == "1.0"' > /dev/null
    echo "$output" | jq -e '.script_version == "1.0.0"' > /dev/null
}

@test "health: no args returns valid JSON with checks" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.checks != null' > /dev/null
    echo "$output" | jq -e '.checks.sudoers_file != null' > /dev/null
    echo "$output" | jq -e '.checks.ssh_dropin_clean != null' > /dev/null
    echo "$output" | jq -e '.checks.nftables_include != null' > /dev/null
    echo "$output" | jq -e '.checks.scripts_present != null' > /dev/null
}

@test "health: checks are strings" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.checks.sudoers_file | type == "string"' > /dev/null
    echo "$output" | jq -e '.checks.ssh_dropin_clean | type == "string"' > /dev/null
    echo "$output" | jq -e '.checks.nftables_include | type == "string"' > /dev/null
    echo "$output" | jq -e '.checks.scripts_present | type == "string"' > /dev/null
}
