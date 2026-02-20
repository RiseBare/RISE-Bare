# RISE - Remote Infrastructure Security & Efficiency

RISE is a professional-grade, agent-less server management platform designed for Debian 12/13+ servers. Manage your infrastructure securely via SSH with a polished desktop client.

## Features

- **Firewall Management** - Atomic rule application with automatic rollback (60s timeout)
- **Docker Control** - Start, stop, restart, list containers
- **System Updates** - APT update orchestration with security patch detection
- **SSH Key Authentication** - TOFU host key verification + per-device SSH keys
- **Multi-Device Support** - Manage servers from multiple computers/phones
- **Health Monitoring** - Server integrity checks (sudoers, SSH config, nftables, scripts)
- **Auto-Update** - Scripts update automatically on each connection
- **3 Security Modes** - Choose SSH security level (password, hybrid, key-only)
- **Internationalization** - 10 languages supported

## Architecture

```
┌─────────────────────────────┐     SSH (port 22)     ┌─────────────────────────────┐
│   RISE Client (JavaFX)      │ ─────────────────────►│   Debian 12/13+ Server     │
│                             │                       │                             │
│  • Firewall Panel          │                       │  /usr/local/bin/           │
│  • Docker Panel            │                       │  • rise-firewall.sh        │
│  • Updates Panel           │                       │  • rise-docker.sh          │
│  • Health Check           │                       │  • rise-update.sh          │
│  • Server List            │                       │  • rise-onboard.sh         │
│  • SSH Keys Manager       │                       │  • rise-health.sh          │
└─────────────────────────────┘                       │  • setup-env.sh            │
                                                         └─────────────────────────────┘
```

## Requirements

### Server (Debian 12/13+)
- Debian 12 (Bookworm) or Debian 13 (Trixie)
- Root access for initial setup
- nftables, jq, openssl

### Client
- Java 21+
- Maven 3.9+

## Quick Start

### 1. Prepare the Server

```bash
curl -s https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts/setup-env.sh | bash -s -- --install
```

### 2. Build the Client

```bash
mvn clean package
```

### 3. Run the Client

```bash
java -jar target/rise-client-1.0.0.jar
```

### 4. Add Your First Server

Launch the client and click "Add Server". Enter your server credentials:
- The app automatically installs RISE on new servers
- If RISE is already installed, it adds your device's SSH key

## Security Features

- **TOFU SSH Host Keys** - First connection validates server fingerprint
- **Per-Device SSH Keys** - Each client device has its own key
- **Limited Sudo Privileges** - Rise-admin has restricted sudo rights
- **Automatic Script Updates** - Scripts update from GitHub on each connection

## Security Modes

When adding a server, choose your SSH security level:

| Mode | Description |
|------|-------------|
| 1 | Keep password access for all users (testing only) |
| 2 | Root/sudo with SSH key only, others can use password |
| 3 | SSH key required for all users (recommended) |

See [SECURITY_MODES.md](docs/SECURITY_MODES.md) for details.

## Support

If you find RISE useful, consider supporting its development:

[![Donate with Stripe](https://img.shields.io/badge/Donate-Support_RISE-635bff?style=for-the-badge)](https://buy.stripe.com/00waEX8WUaso4jB7cL8k801)

## License

Proprietary - All rights reserved
