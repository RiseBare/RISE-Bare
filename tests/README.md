# RISE-Bare Automated Tests

This directory contains automated tests for the RISE-Bare server scripts.

## Test Structure

```
tests/
├── unit/           # Unit tests for individual functions
│   ├── test_firewall.bats
│   ├── test_docker.bats
│   ├── test_update.bats
│   ├── test_health.bats
│   └── test_onboard.bats
├── integration/    # Integration tests for workflows
│   ├── test_firewall_workflow.bats
│   ├── test_health_check.bats
│   └── test_onboarding_flow.bats
└── README.md       # This file
```

## Prerequisites

- **bats** (Bash Automated Testing System) - version 1.0.0 or higher
- **jq** - JSON processor
- **sudo** - for tests requiring root privileges

### Installing bats

```bash
# Clone and install bats
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

Or on Debian/Ubuntu:

```bash
sudo apt-get install bats
```

## Running Tests

### Run all tests

```bash
cd /home/dietpi/.openclaw/workspace/private-projects/RISE-Bare/github/RISE-Bare
bats tests/
```

### Run unit tests only

```bash
bats tests/unit/
```

### Run integration tests only

```bash
bats tests/integration/
```

### Run a specific test file

```bash
bats tests/unit/test_firewall.bats
```

### Run a specific test

```bash
bats tests/unit/test_firewall.bats -r "firewall: --version"
```

## Test Coverage

### rise-firewall.sh (v2.0.0)
- **Unit Tests:**
  - `--version` returns valid JSON
  - No args returns usage error
  - `--flush`, `--rollback`, `--list-rules` return valid JSON
  - `--apply` with invalid JSON returns error
  - `--apply` with invalid port/proto/CIDR returns error
  - `--add-rule`, `--edit-rule`, `--delete-rule` with invalid JSON return error

### rise-docker.sh (v1.0.0)
- **Unit Tests:**
  - `--version` returns valid JSON
  - No args returns usage error
  - `--status`, `--list` return valid JSON
  - Missing container ID returns error
  - Invalid container ID format returns error

### rise-update.sh (v1.0.0)
- **Unit Tests:**
  - `--version` returns valid JSON
  - No args returns usage error
  - `--check`, `--upgrade` return valid JSON

### rise-health.sh (v1.0.0)
- **Unit Tests:**
  - `--version` returns valid JSON
  - No args returns valid JSON with all checks
  - All checks are strings

### rise-onboard.sh (v1.0.0)
- **Unit Tests:**
  - `--version` returns valid JSON
  - No args returns usage error
  - `--check`, `--list-devices` return valid JSON
  - Missing arguments return errors
  - Invalid SSH key format returns error

## Integration Tests

### Firewall Workflow
- Full CRUD operations on firewall rules
- Atomic rule application with rollback
- Rule confirmation and persistence

### Health Check
- System health monitoring
- Sudoers file validation
- SSH configuration cleanup
- Nftables include directory check

### Onboarding Flow
- OTP generation and validation
- SSH key installation
- User creation and sudoers configuration

## Writing New Tests

1. Add test file to `tests/unit/` or `tests/integration/`
2. Use `bats` syntax with `@test` blocks
3. Validate JSON output with `jq`
4. Test both success and error cases
5. Use descriptive test names

Example:

```bash
@test "script: feature returns valid JSON" {
    run bash "$SCRIPT" --feature
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "success"' > /dev/null
}
```

## CI/CD Integration

Tests can be run in CI/CD pipelines:

```yaml
test:
  steps:
    - name: Install bats
      run: |
        git clone https://github.com/bats-core/bats-core.git
        cd bats-core && ./install.sh /usr/local
    - name: Run tests
      run: bats tests/
```

## Troubleshooting

### Tests fail with "command not found"
Ensure all dependencies are installed: `bats`, `jq`, `nft` (for firewall tests)

### Tests fail with permission errors
Some tests require root privileges. Run with `sudo` or ensure the test user has appropriate permissions.

### Tests timeout
Some operations (like `apt-get update`) may take time. Increase timeout in bats config if needed.
