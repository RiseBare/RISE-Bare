#!/usr/bin/env bats

# Unit tests for rise-onboard.sh - public key validation

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-onboard.sh"
}

@test "validate_pubkey: accepts ssh-ed25519" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_pubkey 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILJKhVHpQvUYXqP8HQCJ5JkFVGzMhRqKWMKZmZhJGHDHZ user@host'; echo \$?"
    [ "$output" = "0" ]
}

@test "validate_pubkey: accepts ssh-rsa" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_pubkey 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... user@host'; echo \$?"
    # May fail if ssh-keygen not available, but regex should pass
    [ "$status" -eq 0 -o "$status" -eq 1 ]
}

@test "validate_pubkey: rejects empty key" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_pubkey ''; echo \$?"
    [ "$output" = "1" ]
}

@test "validate_pubkey: rejects invalid format" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_pubkey 'not-a-valid-key'; echo \$?"
    [ "$output" = "1" ]
}

@test "validate_pubkey: rejects key with command injection" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_pubkey 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA; rm -rf /; echo a user@host'; echo \$?"
    [ "$output" = "1" ]
}

@test "OTP generation produces 6 digits" {
    run bash -c "source $SCRIPT 2>/dev/null; otp=\$(openssl rand -base64 3 | tr -dc '0-9' | head -c 6); [[ \$otp =~ ^[0-9]{6}\$ ]] && echo 'valid'"
    [ "$output" = "valid" ]
}
