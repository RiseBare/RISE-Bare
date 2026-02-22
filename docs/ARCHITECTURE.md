# RISE Bare - Technical Architecture

## Overview

```
┌─────────────────────────────┐     SSH (port 22)     ┌─────────────────────────────┐
│   RISE Bare Client         │ ─────────────────────►│   Debian 12/13+ Server     │
│                             │                       │                             │
│  • Firewall Panel          │                       │  /usr/local/bin/           │
│  • Docker Panel            │                       │  • rise-firewall.sh        │
│  • Updates Panel          │                       │  • rise-docker.sh          │
│  • Health Check           │                       │  • rise-update.sh           │
│  • Server List            │                       │  • rise-onboard.sh         │
│  • SSH Keys Manager       │                       │  • rise-health.sh          │
└─────────────────────────────┘                       │  • setup-env.sh            │
                                                         └─────────────────────────────┘
```

---

## Part 1: Server Scripts

### 1.1 `setup-env.sh` - Dependencies Installation

**Version**: `1.0.0`

**Role**: Prepares the server by installing required tools

**Supported commands**:
- `--install`: Installs nftables, jq, openssl, curl, wget, fail2ban, git if missing
- `--check`: Checks if dependencies are present

```bash
# Minimal installation
apt update
apt install -y nftables jq openssl curl wget fail2ban git
```

---

### 1.2 `rise-onboard.sh` - Onboarding and SSH Keys Management

**Version**: `1.0.0`

**Role**: Handles initial installation and SSH keys for client devices

**Commands**:

| Command | Description |
|---------|-------------|
| `--check` | Checks if RISE is already installed |
| `--finalize <ssh_key>` | Finalizes installation, creates `rise-admin` user |
| `--add-device <ssh_key>` | Adds SSH key for a new device |
| `--remove-device <ssh_key>` | Removes SSH key |
| `--list-devices` | Lists all registered keys |

**Behavior**:
- Creates `rise-admin` user with SSH key-only access
- Adds keys to `/home/rise-admin/.ssh/authorized_keys`
- Configures sudoers for rise-admin (RISE scripts access only)

---

### 1.3 `rise-firewall.sh` - Firewall Management with Fail2Ban

**Version**: `1.0.0`

**Role**: Manages NFTables and Fail2Ban rules atomically with automatic rollback

**Commands**:

| Command | Description |
|---------|-------------|
| `--scan` | Scan open ports |
| `--apply` | Apply rules (reads JSON from stdin) |
| `--confirm` | Confirm rules after 60s timeout |
| `--rollback` | Revert to previous rules |

**Fail2Ban**:
- Automatic activation during installation
- SSH monitoring by default
- Logging of blocked attempts

**JSON stdin format**:
```json
[
  {"port": 22, "proto": "tcp", "action": "allow", "cidr": "0.0.0.0/0"},
  {"port": 80, "proto": "tcp", "action": "allow"},
  {"port": 443, "proto": "tcp", "action": "allow"}
]
```

**JSON response format**:
```json
{
  "status": "success",
  "message": "Rules applied",
  "rollback_scheduled": true,
  "data": [...]
}
```

---

### 1.4 `rise-docker.sh` - Docker Management

**Version**: `1.0.0`

**Role**: Controls Docker containers and docker-compose stacks

**Commands**:

| Command | Description |
|---------|-------------|
| `--list` | List all containers |
| `--start <id>` | Start a container |
| `--stop <id>` | Stop a container |
| `--restart <id>` | Restart a container |
| `--update <id>` | Stop, pull latest image, start |
| `--logs <id>` | Display logs |
| `--compose-up <path>` | Run docker-compose |
| `--compose-down <path>` | Stop docker-compose |
| `--compose-pull <path>` | Update images |
| `--compose-add <git_url>` | Clone repo and run docker-compose |

**`--list` response format**:
```json
{
  "status": "success",
  "data": [
    {"id": "abc123", "name": "nginx", "state": "running", "image": "nginx:latest"}
  ]
}
```

---

### 1.5 `rise-update.sh` - APT Updates Management

**Version**: `1.0.0`

**Role**: Manages APT updates with security patch detection and granular updates

**Commands**:

| Command | Description |
|---------|-------------|
| `--check` | Check available updates |
| `--upgrade` | Install all updates |
| `--upgrade-pkgs <packages>` | Update only specified packages (JSON array) |

**`--check-granular` stdin format**:
```json
{"packages": ["nginx", "openssl", "curl"]}
```

**`--check` response format**:
```json
{
  "status": "success",
  "message": "10 updates available (2 security)",
  "data": {
    "packages": [
      {"name": "nginx", "current": "1.24.0", "available": "1.25.0", "security": true},
      {"name": "openssl", "current": "3.0.9", "available": "3.0.11", "security": true}
    ],
    "summary": {"total": 10, "security": 2}
  }
}
```

---

### 1.6 `rise-health.sh` - Integrity Verification

**Version**: `1.0.0`

**Role**: Verifies server configuration integrity

**Checks**:
- `sudoers_file`: rise-admin sudoers file exists
- `ssh_dropin_clean`: No suspicious custom SSH config
- `nftables_include`: NFTables is configured
- `scripts_present`: All RISE scripts are present
- `fail2ban_status`: Fail2Ban is active
- `docker_installed`: Docker is installed
- `docker_containers_rec_by_docker`: Docker containers listed by docker
- `docker_containers_running`: Docker containers currently running
- `rise_version`: Scripts version
- `disk_space`: Disk usage
- `memory`: RAM usage
- `cpu`: CPU stats
- `network`: Network I/O
- `users`: System users

**JSON response format**:
```json
{
  "status": "success",
  "version": "1.0.0",
  "checks": {
    "sudoers_file": "pass",
    "ssh_dropin_clean": "pass",
    "nftables_include": "pass",
    "scripts_present": "pass",
    "fail2ban_status": "pass",
    "docker_installed": "pass",
    "docker_running": "pass",
    "rise_version": "1.0.0",
    "disk_space": {"total": "100G", "used": "50G", "free": "50G", "percent": 50},
    "memory": {"total": "16G", "used": "8G", "free": "8G", "percent": 50},
    "cpu": {"cores": 4, "usage": 25},
    "network": {"in": "1GB", "out": "500MB"},
    "users": [{"name": "root", "sudoers": true}, {"name": "rise-admin", "sudoers": false}]
  }
}
```

---

## Part 2: RISE Bare Client

### 2.1 Network Architecture

**Protocol**: SSH (port 22)

**Connection methods**:
1. **Password**: Initial connection with login/password (for onboarding)
2. **Key**: Connection with Ed25519 private key (after onboarding)

**TOFU Security**:
- Saves server fingerprint on first connection
- Prompts confirmation if fingerprint changes (possible MITM attack)

---

### 2.2 User Interface

**Windows**:

1. **Main Window**
   - List of configured servers
   - Add/Remove Server buttons
   - 4 tabs: Security (Firewall, fail2ban), Services (Docker), Updates, Health
   - Settings button

2. **Onboarding Dialog**
   - Server name
   - IP/Hostname
   - SSH port (default: 22)
   - Username (root or sudo user)
   - Password
   - **3 SSH security modes**:
     - Mode 1: Password for all (testing only)
     - Mode 2: SSH key for root, password for other users
     - Mode 3: SSH key for all (recommended)

3. **Settings Dialog**
   - Language selector (10 languages)
   - Checkbox "Auto-update scripts on connect"
   - Stripe donation link
   - "Check for updates" button

---

### 2.3 Onboarding Flow

```
1. User enters credentials (host, port, user, password)
2. Client SSH connects with password
3. Script --check: RISE installed?

   YES → --add-device <public_ssh_key>
   Generate Ed25519 key for client device if needed
   Save private key locally to rise-admin user

   NO → --install (setup-env.sh)
        --finalize <public_ssh_key>
        Configure SSH security mode
4. Create rise-admin user
5. Generate Ed25519 key for client device
6. Save private key locally to rise-admin user
7. Propose 3 SSH security modes and apply user's choice
```

---

### 2.4 Local Data Formats

**Servers config**:
```json
{
  "servers": [
    {
      "id": "uuid",
      "name": "My Server",
      "host": "192.168.1.100",
      "port": 22,
      "username": "rise-admin",
      "password": null,
      "securityMode": "MODE_3"
    }
  ]
}
```

**Settings**:
```json
{
  "language": "en",
  "autoUpdateScripts": true,
  "lastUpdateCheck": "2024-01-15T10:30:00Z",
  "clientVersion": "1.0.0"
}
```

---

### 2.5 Internationalization (i18n)

**Source**: Versioned JSON files on GitHub
- URL: `https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/i18n/{lang}.json?version={version}`
- Version: Each file contains a `version` field
- Languages: en, fr, de, es, zh, ja, ko, th, pt, ru
- Local cache with version check before update

**i18n file format**:
```json
{
  "version": "1.0.0",
  "app.title": "RISE Bare",
  ...
}
```

---

## Part 3: Client Options

### 3.1 Firewall
- [x] Scan open ports
- [x] Add rule (port, proto, action, CIDR)
- [x] Remove rule
- [x] Apply rules
- [x] Confirm (after 60s)
- [x] Rollback
- [x] Fail2Ban status
- [x] Daily/weekly/monthly banned IPs report
- [x] Fail2Ban rules editing
- [ ] **In-App Purchase**: Daily/weekly/monthly banned IPs report, Fail2Ban rules editing

### 3.2 Docker
- [x] List containers
- [x] Start
- [x] Stop
- [x] Restart
- [x] Update (stop, pull, start)
- [x] Logs
- [x] Docker Compose: up/down/pull
- [x] Visual Docker Compose editor
- [x] **Docker Compose: add via GitHub URL**
- [ ] **In-App Purchase**: Visual Docker Compose editor, Docker Compose add via GitHub URL

### 3.3 Updates
- [x] Check for updates
- [x] Install all updates
- [x] **Granular package check**
- [x] **Granular update (selected packages)**
- [ ] **In-App Purchase**: Granular package selection

### 3.4 Health
- [x] Full integrity check
- [x] Display status (pass/fail, scripts version)
- [x] Automated email alerts
- [x] Server stats: disk space (total/used/free/%), RAM (total/used/free/%), CPU (cores, usage for 1min/5min/30min/1h/6h/12h/24h/3d/1w), network I/O (1min/5min/30min/1h/6h/12h/24h/3d/1w), all users (with sudoers/sudo group mention)
- [ ] **In-App Purchase**: Server stats, Automated email alerts

### 3.5 Server Management
- [x] Add server
- [x] Remove server
- [x] Auto-connect
- [ ] **In-App Purchase**: Unlimited servers (free limit: 3)

---

## Part 4: In-App Purchase System (to implement)

### 4.1 Free Features

| Feature | Limit |
|---------|-------|
| Servers managed | 3 |
| APT upgrade | All packages |
| Docker | Start/Stop/Restart/Update |
| Docker Compose | up/down/pull |
| Firewall | Scan/Add/Remove/Apply rules, status |
| Health | Basic integrity check |

### 4.2 Paid Features (In-App Purchase)

| Feature | Description |
|---------|-------------|
| Unlimited servers | Add more than 3 servers |
| APT granular | Select specific packages to update |
| Docker Compose Editor | Visual editor for docker-compose files |
| Docker Compose GitHub | Add repository GitHub URL directly |
| Firewall Reports | Daily/weekly/monthly banned IPs reports |
| Firewall Rules Editing | Custom Fail2Ban rules |
| Server Stats | Detailed disk/RAM/CPU/network stats |
| Email Alerts | Automated health alerts via email |

### 4.3 Implementation

Each paid feature must:
1. Check purchase status via API
2. If not purchased: show "Premium feature" dialog with purchase/donation button
3. If purchased: execute the feature normally

---

## Part 5: Version Management

### 5.1 Versioning Strategy

**Scripts**: Each script contains its own version
- `setup-env.sh`: `VERSION="1.0.0"`
- `rise-onboard.sh`: `VERSION="1.0.0"`
- etc.

**i18n files**: Each file contains a `version` field
- `en.json`: `"version": "1.0.0"`

**Client**: Version in settings
- `~/.rise/settings.json`: `"clientVersion": "1.0.0"`

### 5.2 Update Checking

```
1. On startup, client checks settings.lastUpdateCheck
2. If > 6h or autoUpdateScripts=true:
   a. Fetch version.json from GitHub
   b. For each script: compare local vs remote version
   c. For each i18n file: compare version
   d. Display list of available updates
3. User can choose: update all, or partial selection
```

---

## Appendix: Scripts <-> UI Mapping

| UI Action | Script | Command |
|-----------|--------|---------|
| Scan ports | rise-firewall | --scan |
| Add rule | rise-firewall | --apply (stdin) |
| Remove rule | rise-firewall | --apply (without rule) |
| Confirm rules | rise-firewall | --confirm |
| Rollback | rise-firewall | --rollback |
| List containers | rise-docker | --list |
| Start container | rise-docker | --start |
| Stop container | rise-docker | --stop |
| Restart container | rise-docker | --restart |
| Update container | rise-docker | --update |
| Docker compose up | rise-docker | --compose-up |
| Docker compose down | rise-docker | --compose-down |
| Docker compose pull | rise-docker | --compose-pull |
| Add GitHub compose | rise-docker | --compose-add |
| Check updates | rise-update | --check |
| Check granular | rise-update | --check-granular (stdin) |
| Upgrade all | rise-update | --upgrade |
| Upgrade selected | rise-update | --upgrade-pkgs (stdin) |
| Health check | rise-health | (no args) |
| Add device | rise-onboard | --add-device |
| Remove device | rise-onboard | --remove-device |
| List devices | rise-onboard | --list-devices |
