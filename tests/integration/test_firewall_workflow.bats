#!/usr/bin/env bats

# Integration tests for firewall workflow

SCRIPT_DIR="$BATS_TEST_DIRNAME/../../scripts"

@test "firewall: --version returns valid JSON" {
    run bash "$SCRIPT_DIR/rise-firewall.sh" --version
    echo "$output"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --scan returns valid JSON" {
    run sudo bash "$SCRIPT_DIR/rise-firewall.sh" --scan
    echo "$output"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --scan returns data array" {
    run sudo bash "$SCRIPT_DIR/rise-firewall.sh" --scan
    run bash -c "echo '$output' | jq -e '.data | type == \"array\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --apply with valid rules returns success" {
    run sudo bash -c "echo '[{\"port\": 22, \"proto\": \"tcp\", \"action\": \"allow\"}]' | $SCRIPT_DIR/rise-firewall.sh --apply"
    echo "$output"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --apply with invalid JSON returns error" {
    run sudo bash -c "echo 'invalid json' | $SCRIPT_DIR/rise-firewall.sh --apply"
    [ "$status" -ne 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"error\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --apply with invalid port returns error" {
    run sudo bash -c "echo '[{\"port\": 99999, \"proto\": \"tcp\", \"action\": \"allow\"}]' | $SCRIPT_DIR/rise-firewall.sh --apply"
    [ "$status" -ne 0 ]
    run bash -c "echo '$output' | jq -e '.code == \"ERR_INVALID_RULE\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --apply with invalid proto returns error" {
    run sudo bash -c "echo '[{\"port\": 22, \"proto\": \"invalid\", \"action\": \"allow\"}]' | $SCRIPT_DIR/rise-firewall.sh --apply"
    [ "$status" -ne 0 ]
}

@test "firewall: --apply with invalid CIDR returns error" {
    run sudo bash -c "echo '[{\"port\": 22, \"proto\": \"tcp\", \"action\": \"allow\", \"cidr\": \"999.999.999.999/24\"}]' | $SCRIPT_DIR/rise-firewall.sh --apply"
    [ "$status" -ne 0 ]
}

@test "firewall: --confirm with no pending rules returns error" {
    # Clean up any pending rules first
    sudo rm -f /var/lib/rise/pending-rules.nft 2>/dev/null || true
    run sudo bash "$SCRIPT_DIR/rise-firewall.sh" --confirm
    [ "$status" -ne 0 ]
    run bash -c "echo '$output' | jq -e '.code == \"ERR_OPERATION_FAILED\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --rollback returns success" {
    run sudo bash "$SCRIPT_DIR/rise-firewall.sh" --rollback
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}

@test "firewall: --flush returns success" {
    run sudo bash "$SCRIPT_DIR/rise-firewall.sh" --flush
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.status == \"success\"'"
    [ "$status" -eq 0 ]
}
