# SSH Security Modes for RISE Bare

This document explains the three SSH security modes available when onboarding a server with RISE Bare.

## Modes Summary

| Mode | Root Access | Other Users Access | Recommended |
|------|-------------|-------------------|-------------|
| **Mode 1** | Password + Key | Password + Key | No |
| **Mode 2** | Key only | Password + Key | For transition |
| **Mode 3** | Key only | Key only | **Yes** |

---

## Mode 1: Password Access for All (NOT RECOMMENDED)

```bash
# Configuration: PasswordAuthentication yes
```

### Description
- The account used for onboarding (root or sudo user) remains accessible by password
- All SSH connections with password remain possible
- No authentication restrictions

### Risks
- **Brute force attacks** possible on the account
- If the password is compromised, the attacker has full access
- Vulnerable to keyloggers and phishing
- Does not follow security best practices

### When to Use
- Only in test/dev environment
- Temporary migration to Mode 3
- Machines without direct internet access

---

## Mode 2: Root by Key, Others by Password (TRANSITION)

```bash
# sshd_config configuration:
PermitRootLogin prohibit-password
PasswordAuthentication yes
```

### Description
- The root account (or sudo account used) is only accessible by SSH key
- Other system users can still use their password
- Transition to Mode 3

### Advantages
- Main administrative account is secured by SSH key
- SSH keys are harder to compromise than passwords
- Reduced attack surface

### Disadvantages
- Other accounts remain vulnerable to password attacks
- Need to remember which machine uses which mode

### When to Use
- During transition phase
- Servers with multiple legitimate users using passwords

---

## Mode 3: SSH Key Only (RECOMMENDED)

```bash
# sshd_config configuration:
PermitRootLogin prohibit-password
PasswordAuthentication no
```

### Description
- **All** SSH connections require an SSH key
- The `rise-admin` account is **always** in Mode 3 (key only)
- The account used for onboarding is also restricted to keys

### Advantages
- **Maximum security**: No password to compromise
- Ed25519 SSH keys are cryptographically superior to passwords
- No risk of brute force attacks
- Compliance with modern security standards
- Easier auditing (key traceability)

### Disadvantages
- Each new device must be registered via the RISE Bare app
- Loss of private key = loss of access (plan for backup keys)
- Longer initial configuration

### When to Use
- **Production** (highly recommended)
- Servers exposed to the internet
- Sensitive environments
- PCI-DSS, SOC2, ISO 27001 compliance

---

## Managing SSH Keys

### Adding a New Device

#### Method 1: From an Existing Device (RISE OTP)

This is the recommended method when the server is already in Mode 2 or Mode 3 (password auth disabled).

On the **existing device** (Device A) that is already connected to the server:
1. Open the RISE Bare app
2. Select the server
3. Go to the **Security** tab
4. Click **"Add new RISE Bare client"**
5. A 6-digit OTP code is displayed with a 30-second countdown
6. Communicate this code to the user of the new device (Device B)

On the **new device** (Device B):
1. Open the RISE Bare app
2. Click **"Add Server"**
3. Select the **"RISE OTP"** tab
4. Enter the server IP/hostname and the OTP code
5. The app automatically connects and adds the SSH key

#### Method 2: Password Authentication (Mode 1 servers only)

If the server is still in Mode 1 (password auth enabled):
1. Launch the app on the new device
2. Click **"Add Server"**
3. Enter the server credentials (IP, username, password)
4. The app detects that RISE is already installed
5. Automatically adds the new SSH key

#### Method 3: Server Command Line

```bash
# Generate a key on the new device
ssh-keygen -t ed25519 -C "my-device-name"

# Add it manually (if you already have SSH access)
cat ~/.ssh/id_ed25519.pub
# Copy this key and add via RISE app or manually:
# echo "ssh-ed25519 AAAA..." >> /home/rise-admin/.ssh/authorized_keys
```

### Revoking a Device

**Important:** You cannot revoke your own access from the current device. To remove your current device, you must:
1. Add a new device via OTP from this device
2. Connect from the new device
3. Revoke this device's key from there

#### Via RISE Bare App:
1. Select the server
2. Go to the **Security** tab
3. View the list of registered devices
4. Click **"Revoke"** next to the key to remove

#### Via Command Line:
```bash
# List registered keys
rise-onboard.sh --list-devices

# Remove a specific key
rise-onboard.sh --remove-device "ssh-ed25519 AAAA..."
```

### Backup Keys

It is **highly recommended** to:
1. Generate a backup key on a secure medium (encrypted USB drive)
2. Add it during initial onboarding or after
3. Store this backup key in a physical safe

---

## FAQ

**Q: What if I lose all my keys?**
A: Connect physically to the server (console) or via a recovery mechanism (IPMI, cloud console) and add a new key manually.

**Q: Can I have multiple keys for the same device?**
A: Yes, it's even recommended to separate uses (one key for laptop, one for backup).

**Q: Are RSA keys supported?**
A: Yes, but Ed25519 is recommended (more secure and faster).

**Q: Does Mode 3 block SFTP?**
A: No, SFTP works with SSH keys exactly like with passwords.

---

*Document generated for RISE Bare v1.0.0*
