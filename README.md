# RISE Bare - Remote Infrastructure Security & Efficiency

RISE Bare is a professional-grade, agent-less server management platform designed for Debian 12/13+ servers. Manage your infrastructure securely via SSH with a polished mobile and desktop client.

## Features

- **Firewall Management** - Atomic rule application with automatic rollback (90s timeout)
- **Docker Control** - Start, stop, restart, list containers and compose projects
- **System Updates** - APT update orchestration with security patch detection
- **SSH Key Authentication** - TOFU host key verification + per-device SSH keys
- **Multi-Device Support** - Manage servers from multiple computers/phones via OTP
- **Health Monitoring** - Server integrity checks (sudoers, SSH config, nftables, scripts)
- **Auto-Update** - Scripts update automatically on startup and every 6 hours
- **3 Security Modes** - Choose SSH security level (password, hybrid, key-only)
- **Internationalization** - 10 languages supported

## Architecture

```
┌─────────────────────────────┐     SSH (port 22)     ┌─────────────────────────────┐
│   RISE Client (Flutter)      │ ─────────────────────►│   Debian 12/13+ Server     │
│                             │                       │                             │
│  • Firewall Panel           │                       │  /usr/local/bin/           │
│  • Docker Panel             │                       │  • rise-firewall.sh        │
│  • Updates Panel           │                       │  • rise-docker.sh          │
│  • Health Check            │                       │  • rise-update.sh          │
│  • Server List             │                       │  • rise-onboard.sh         │
│  • Security Tab            │                       │  • rise-health.sh          │
│    (SSH Keys, Modes)       │                       │  • setup-env.sh            │
└─────────────────────────────┘                       └─────────────────────────────┘
```

## Requirements

### Server (Debian 12/13+)
- Debian 12 (Bookworm) or Debian 13 (Trixie)
- SSH access with sudo/root privileges
- Internet access (to download scripts from GitHub)

### Client

**Download from:**
- [Google Play](https://play.google.com/store) (Android)
- [Apple App Store](https://apps.apple.com) (iOS)
- [GitHub Releases](https://github.com/RiseBare/RISE-Bare/releases) (macOS, Linux, Windows)

## Quick Start

### 1. Download the Client

Download from your platform's store or from GitHub Releases.

### 2. Add Your Server

Click "Add Server" and enter:
- Server name (e.g., "My VPS")
- IP address or hostname
- SSH port (default: 22)
- Username (root or sudo user)
- Password

The app will automatically:
- Install RISE scripts on your server
- Create a dedicated `rise-admin` account
- Add your device's SSH key
- Configure SSH security based on your chosen mode

That's it! Your server is now managed by RISE Bare.

## Security Features

- **TOFU SSH Host Keys** - First connection validates server fingerprint
- **Per-Device SSH Keys** - Each client device has its own Ed25519 key
- **Limited Sudo Privileges** - rise-admin has restricted sudo rights for RISE scripts only
- **Automatic Script Updates** - Scripts update from GitHub on startup and every 6 hours
- **OTP Device Registration** - Add new devices securely via rolling 6-digit codes

## Security Modes

When adding a server, choose your SSH security level:

| Mode | Description |
|------|-------------|
| 1 | Keep password access for all users (testing only) |
| 2 | Root/sudo with SSH key only, others can use password |
| 3 | SSH key required for all users (recommended) |

See [SECURITY_MODES.en.md](docs/SECURITY_MODES.en.md) for details.

## Support

If you find RISE Bare useful, consider supporting its development:

[![Donate with Stripe](https://img.shields.io/badge/Donate-Support_RISE-635bff?style=for-the-badge)](https://buy.stripe.com/00waEX8WUaso4jB7cL8k801)

## License

Proprietary - All rights reserved
