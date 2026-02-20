# RISE - Remote Infrastructure Security & Efficiency

RISE is a professional-grade, agent-less server management platform designed for Debian 12/13+ servers. Manage your infrastructure securely via SSH with a polished desktop client.

## Features

- **Firewall Management** - Atomic rule application with automatic rollback (60s timeout)
- **Docker Control** - Start, stop, restart, list containers
- **System Updates** - APT update orchestration with security patch detection
- **Zero-Trust Onboarding** - OTP + SSH key TOFU validation
- **Health Monitoring** - Server integrity checks (sudoers, SSH config, nftables, scripts)

## Architecture

```
┌─────────────────────────────┐     SSH (port 22)     ┌─────────────────────────────┐
│   RISE Client (JavaFX)     │ ─────────────────────►│   Debian 12/13+ Server      │
│                             │                       │                             │
│  • Firewall Panel          │                       │  /usr/local/bin/           │
│  • Docker Panel           │                       │  • rise-firewall.sh        │
│  • Updates Panel          │                       │  • rise-docker.sh          │
│  • Health Check           │                       │  • rise-update.sh           │
│  • Server List            │                       │  • rise-onboard.sh         │
└─────────────────────────────┘                       │  • rise-health.sh          │
                                                         │  • setup-env.sh            │
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

### 2. Onboard a Server

```bash
sudo /usr/local/bin/rise-onboard.sh --generate-otp
```

### 3. Build the Client

```bash
mvn clean package
```

### 4. Run the Client

```bash
java -jar target/rise-client-1.0.0.jar
```

## Security Features

- Atomic Operations with automatic rollback
- TOFU SSH host key verification
- Limited sudo privileges
- OTP authentication for onboarding

## Support

If you find RISE useful, consider supporting its development:
<script async
  src="https://js.stripe.com/v3/buy-button.js">
</script>

<stripe-buy-button
  buy-button-id="buy_btn_1T2qBtFglBlFeB6Rh7OXj2YB"
  publishable-key="pk_live_51T2pbOFglBlFeB6RtCLvJhWgDVo0JJdU6x1fYwIXAmK8KKEd4bl3LD2cPlUbdLzdvALf6DTEjSJYBXtD4tgdBcCH00vlve9c3k"
>
</stripe-buy-button>

## License

Proprietary - All rights reserved
