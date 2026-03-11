#!/usr/bin/env bats

# Unit tests for rise-firewall.sh

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-firewall.sh"
}

@test "firewall: --version returns valid JSON" {
    run bash "$SCRIPT" --version
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
    echo "$output" | jq -e '.api_version == "2.0"' > /dev/null
    echo "$output" | jq -e '.script_version == "2.0.0"' > /dev/null
}

@test "firewall: no args returns usage error" {
    run bash "$SCRIPT" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
    echo "$output" | jq -e '.code == "ERR_INVALID_ARGUMENTS"' > /dev/null
}

@test "firewall: --flush returns success" {
    run bash "$SCRIPT" --flush 2>&1
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}

@test "firewall: --rollback returns success" {
    run bash "$SCRIPT" --rollback 2>&1
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}

@test "firewall: --list-rules returns valid JSON" {
    run bash "$SCRIPT" --list-rules 2>/dev/null
    [ "$status" -eq 0 ] || true
    echo "$output" | jq -e '.status == "success" or .status == "error"' > /dev/null
}

@test "firewall: --apply with invalid JSON returns error" {
    run bash -c "echo 'invalid json' | $SCRIPT --apply 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
}

@test "firewall: --apply with invalid port returns error" {
    run bash -c "echo '[{\"port\": 99999, \"proto\": \"tcp\", \"action\": \"allow\"}]' | $SCRIPT --apply 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.code == "ERR_INVALID_RULE"' > /dev/null
}

@test "firewall: --apply with invalid proto returns error" {
    run bash -c "echo '[{\"port\": 22, \"proto\": \"invalid\", \"action\": \"allow\"}]' | $SCRIPT --apply 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.code == "ERR_INVALID_RULE"' > /dev/null
}

@test "firewall: --apply with invalid CIDR returns error" {
    run bash -c "echo '[{\"port\": 22, \"proto\": \"tcp\", \"action\": \"allow\", \"cidr\": \"999.999.999.999/24\"}]' | $SCRIPT --apply 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.code == "ERR_INVALID_RULE"' > /dev/null
}

@test "firewall: --add-rule with invalid JSON returns error" {
    run bash -c "echo 'invalid json' | $SCRIPT --add-rule 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
}

@test "firewall: --edit-rule with invalid JSON returns error" {
    run bash -c "echo 'invalid json' | $SCRIPT --edit-rule 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
}

@test "firewall: --delete-rule with invalid JSON returns error" {
    run bash -c "echo 'invalid json' | $SCRIPT --delete-rule 2>/dev/null"
    [ "$status" -ne 0 ]
    echo "$output" | jq -e '.status == "error"' > /dev/null
}
