#!/usr/bin/env bats

# Unit tests for rise-firewall.sh - CIDR validation

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rise-firewall.sh"
}

@test "validate_cidr: valid CIDR 10.0.0.0/8" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '10.0.0.0/8'; echo \$?"
    [ "$output" = "0" ]
}

@test "validate_cidr: valid CIDR 192.168.1.0/24" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '192.168.1.0/24'; echo \$?"
    [ "$output" = "0" ]
}

@test "validate_cidr: valid CIDR with host bits (accepted)" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '10.0.0.1/8'; echo \$?"
    [ "$output" = "0" ]
}

@test "validate_cidr: invalid prefix > 32" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '10.0.0.0/33'; echo \$?"
    [ "$output" = "1" ]
}

@test "validate_cidr: invalid octet > 255" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '256.0.0.0/8'; echo \$?"
    [ "$output" = "1" ]
}

@test "validate_cidr: rejects IPv6" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '2001:db8::1/64'; echo \$?"
    [ "$output" = "1" ]
}

@test "validate_cidr: invalid format" {
    run bash -c "source $SCRIPT 2>/dev/null; validate_cidr '10.0.0.0'; echo \$?"
    [ "$output" = "1" ]
}
