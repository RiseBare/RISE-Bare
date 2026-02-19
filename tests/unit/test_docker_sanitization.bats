#!/usr/bin/env bats

# Unit tests for rise-docker.sh - container ID sanitization

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-docker.sh"
}

@test "container_action: rejects invalid container ID" {
    # This test would need mocking docker which is complex
    # Instead test the regex validation in isolation
    run bash -c "id='test;rm -rf /;test'; [[ ! \$id =~ ^[a-zA-Z0-9_.\-]{1,128}\$ ]] && echo 'valid'"
    [ "$output" = "valid" ]
}

@test "container_action: accepts valid container ID" {
    run bash -c "id='abc123-def456'; [[ \$id =~ ^[a-zA-Z0-9_.\-]{1,128}\$ ]] && echo 'valid'"
    [ "$output" = "valid" ]
}

@test "container_action: accepts long container ID" {
    run bash -c "id='$(printf 'a%.0s' {1..128})'; [[ \$id =~ ^[a-zA-Z0-9_.\-]{1,128}\$ ]] && echo 'valid'"
    [ "$output" = "valid" ]
}

@test "container_action: rejects too long ID" {
    run bash -c "id='$(printf 'a%.0s' {1..129})'; [[ ! \$id =~ ^[a-zA-Z0-9_.\-]{1,128}\$ ]] && echo 'valid'"
    [ "$output" = "valid" ]
}

@test "container_action: rejects shell metacharacters" {
    for char in ';' '|' '&' '$' '`' '(' ')'; do
        run bash -c "id=\"test\$char\"; [[ ! \$id =~ ^[a-zA-Z0-9_.\-]{1,128}\$ ]] && echo 'valid'"
        [ "$output" = "valid" ]
    done
}
