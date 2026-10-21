# remote-access-setup

One script to set up **secure remote SSH access to your own machine from anywhere** — across any network, on any OS — so you can connect to it (and run tools like [Claude Code](https://claude.com/claude-code)) from another computer.

> ⚠️ **Use only on machines you own or are explicitly authorized to administer.**
> This sets up access for *you* to *your own* devices. It is not for installing on other people's machines.

## What it does

The hard part of "connect from any network" is that most machines sit behind a home router, NAT, or firewall with no public IP and no open ports. Rather than forwarding ports or exposing SSH to the internet, this uses **[Tailscale](https://tailscale.com)** — a WireGuard-based mesh VPN — which creates a private, end-to-end-encrypted network between your own devices and punches through NAT automatically.

The script:

1. **Detects your OS** (Linux distro, macOS, or Windows).
2. **Installs Tailscale.**
3. **Enables the native SSH server** (`sshd` on Linux, Remote Login on macOS, OpenSSH Server on Windows).
4. **Brings up Tailscale with [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh)** so SSH auth is tied to your Tailscale identity — no manual key management.
5. **Prints the address** you use to connect from your other machine.

## Prerequisites

- A free **Tailscale account** — sign up at https://login.tailscale.com (Google/GitHub/Microsoft/email).
- Admin/root on the machine you're setting up.

You install Tailscale on **both** machines: this target machine (via the script) and whatever machine you'll connect *from* (the regular Tailscale app).

## Usage

### Linux / macOS

```bash
# Run directly:
curl -fsSL https://raw.githubusercontent.com/Arryn21/remote-access-setup/main/setup.sh | bash

# Or clone and run:
git clone https://github.com/Arryn21/remote-access-setup.git
cd remote-access-setup
chmod +x setup.sh
./setup.sh
```

During setup a **login URL** is printed — open it in a browser and approve this device on your Tailscale account.

### Windows

Open **PowerShell as Administrator**, then:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
irm https://raw.githubusercontent.com/Arryn21/remote-access-setup/main/setup.ps1 | iex
```

Or clone and run `.\setup.ps1` from an elevated PowerShell.

## Connecting

After setup finishes it prints something like:

```
ssh you@your-machine.your-tailnet.ts.net
```

From any other device signed into **your** Tailscale account, run that command. Then start Claude Code:

```bash
claude
```

## How "any network" works

| Situation | Handled by |
|---|---|
| Machine behind home NAT | Tailscale NAT traversal (direct WireGuard tunnel) |
| Strict firewall / CGNAT | Tailscale DERP relays as fallback |
| Changing IP addresses | Stable tailnet hostname, not a raw IP |
| Different OSes | Script branches per-OS; Tailscale has native clients for all three |

## Security

- Only devices authenticated to **your** Tailscale account can reach this machine — nothing is exposed to the public internet.
- All traffic is end-to-end encrypted (WireGuard).
- You can restrict *which* of your devices (or users) may SSH in via **ACLs** in the [Tailscale admin console](https://login.tailscale.com/admin/acls).
- To revoke access, remove the device from your tailnet or disable Tailscale SSH.

## Uninstall / undo

- **Disconnect:** `tailscale down` (temporary) or remove the machine from the Tailscale admin console.
- **Stop SSH:**
  - Linux: `sudo systemctl disable --now ssh` (or `sshd`)
  - macOS: `sudo systemsetup -setremotelogin off`
  - Windows (elevated): `Stop-Service sshd; Set-Service sshd -StartupType Disabled`
- **Remove Tailscale:** uninstall via your package manager / Add-Remove Programs.

## License

MIT — see [LICENSE](LICENSE).
