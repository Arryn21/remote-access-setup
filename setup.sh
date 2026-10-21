#!/usr/bin/env bash
#
# setup.sh — Remote access setup for Linux & macOS
#
# Sets up secure remote SSH access to THIS machine from anywhere, using
# Tailscale (a WireGuard mesh VPN) so it works behind any NAT/firewall
# without opening ports or exposing SSH to the public internet.
#
# What it does:
#   1. Detects your OS (Linux distro or macOS).
#   2. Installs Tailscale.
#   3. Enables the native SSH server (sshd / Remote Login).
#   4. Brings up Tailscale with Tailscale SSH enabled, and prints the
#      login URL so you can attach this device to YOUR Tailscale account.
#   5. Prints the address you use to connect from your other machine.
#
# Run ONLY on machines you own or are explicitly authorized to administer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Arryn21/remote-access-setup/main/setup.sh | bash
#   # or, after cloning:
#   ./setup.sh
#
set -euo pipefail

# ---- pretty output ---------------------------------------------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"
  RED="$(printf '\033[31m')"; GRN="$(printf '\033[32m')"
  YLW="$(printf '\033[33m')"; BLU="$(printf '\033[34m')"
  RST="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi
info()  { printf '%s==>%s %s\n' "$BLU$BOLD" "$RST" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$GRN" "$RST" "$*"; }
warn()  { printf '%swarn%s %s\n' "$YLW" "$RST" "$*" >&2; }
die()   { printf '%s err%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
step()  { printf '\n%s%s%s\n' "$BOLD" "$*" "$RST"; }

# ---- privilege helper ------------------------------------------------------
# Use sudo for privileged commands unless we are already root.
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "This script needs root for installs. Install sudo or run as root."
  fi
fi
run_priv() { if [ -n "$SUDO" ]; then $SUDO "$@"; else "$@"; fi; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---- OS detection ----------------------------------------------------------
OS="$(uname -s)"
case "$OS" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *)      die "Unsupported OS '$OS'. Use setup.ps1 on Windows." ;;
esac

step "Remote access setup  (platform: $PLATFORM)"

# ===========================================================================
# 1. Install Tailscale
# ===========================================================================
install_tailscale_linux() {
  if have tailscale; then ok "Tailscale already installed ($(tailscale version | head -n1))"; return; fi
  info "Installing Tailscale via official installer..."
  # Tailscale's installer detects the distro and sets up the repo + service.
  curl -fsSL https://tailscale.com/install.sh | run_priv sh
  ok "Tailscale installed"
}

install_tailscale_macos() {
  if have tailscale; then ok "Tailscale already installed"; return; fi
  if have brew; then
    info "Installing Tailscale via Homebrew..."
    brew install tailscale
    # The brew (open-source CLI) build needs its system daemon installed.
    run_priv tailscaled install-system-daemon || warn "Could not install tailscaled daemon automatically."
    ok "Tailscale installed"
  else
    warn "Homebrew not found."
    cat <<EOF
Install Tailscale one of these ways, then re-run this script:
  - Mac App Store / https://tailscale.com/download/macos  (GUI app), or
  - Install Homebrew (https://brew.sh) then: brew install tailscale
EOF
    die "Tailscale not installed."
  fi
}

# ===========================================================================
# 2. Enable the native SSH server
# ===========================================================================
enable_ssh_linux() {
  info "Ensuring an SSH server is installed and running..."
  if ! have sshd && ! [ -x /usr/sbin/sshd ]; then
    if   have apt-get; then run_priv apt-get update -y && run_priv apt-get install -y openssh-server
    elif have dnf;     then run_priv dnf install -y openssh-server
    elif have yum;     then run_priv yum install -y openssh-server
    elif have pacman;  then run_priv pacman -Sy --noconfirm openssh
    elif have zypper;  then run_priv zypper install -y openssh
    elif have apk;     then run_priv apk add openssh
    else warn "Unknown package manager — install openssh-server manually."
    fi
  fi
  # Start & enable the service across common service names / init systems.
  if have systemctl; then
    for svc in ssh sshd; do
      if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        run_priv systemctl enable --now "$svc" && ok "sshd enabled ($svc)"; return
      fi
    done
    run_priv systemctl enable --now ssh 2>/dev/null || run_priv systemctl enable --now sshd 2>/dev/null \
      || warn "Could not start sshd via systemctl; start it manually."
  elif have rc-service; then
    run_priv rc-update add sshd default 2>/dev/null || true
    run_priv rc-service sshd start 2>/dev/null && ok "sshd started (openrc)" || warn "Start sshd manually."
  elif have service; then
    run_priv service ssh start 2>/dev/null || run_priv service sshd start 2>/dev/null || warn "Start sshd manually."
  else
    warn "No known service manager; ensure sshd is running."
  fi
}

enable_ssh_macos() {
  info "Enabling Remote Login (SSH) ..."
  if run_priv systemsetup -getremotelogin 2>/dev/null | grep -qi 'On'; then
    ok "Remote Login already on"
  else
    run_priv systemsetup -setremotelogin on && ok "Remote Login enabled" \
      || warn "Enable it manually: System Settings > General > Sharing > Remote Login."
  fi
}

# ===========================================================================
# 3. Bring up Tailscale (with Tailscale SSH)
# ===========================================================================
tailscale_up() {
  info "Bringing up Tailscale with Tailscale SSH enabled..."
  echo "${DIM}If this device isn't logged in yet, a browser login URL will appear below.${RST}"
  echo "${DIM}Open it and approve the device on YOUR Tailscale account.${RST}"
  # --ssh ties SSH auth to your tailnet identity (ACL-gated, no key juggling).
  run_priv tailscale up --ssh || die "tailscale up failed. Re-run: sudo tailscale up --ssh"
  ok "Tailscale is up"
}

# ===========================================================================
# run
# ===========================================================================
case "$PLATFORM" in
  linux)
    step "1/4  Install Tailscale"; install_tailscale_linux
    step "2/4  Enable SSH server"; enable_ssh_linux
    step "3/4  Connect to your tailnet"; tailscale_up
    ;;
  macos)
    step "1/4  Install Tailscale"; install_tailscale_macos
    step "2/4  Enable SSH server"; enable_ssh_macos
    step "3/4  Connect to your tailnet"; tailscale_up
    ;;
esac

# ===========================================================================
# 4. Report connection details
# ===========================================================================
step "4/4  Done — how to connect"
TS_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
TS_HOST="$(tailscale status --json 2>/dev/null | grep -o '"DNSName":"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's/\.$//' || true)"
USER_NAME="${SUDO_USER:-$(id -un)}"

echo
ok "This machine is reachable on your tailnet."
echo "   ${BOLD}From your other computer${RST} (also signed into your Tailscale account):"
[ -n "$TS_HOST" ] && echo "     ssh ${USER_NAME}@${TS_HOST}"
[ -n "$TS_IP" ]   && echo "     ssh ${USER_NAME}@${TS_IP}    ${DIM}(by IP)${RST}"
if [ -z "$TS_HOST" ] && [ -z "$TS_IP" ]; then
  warn "Could not read the Tailscale address yet. Run 'tailscale status' once login completes."
fi
echo
echo "   Then run Claude Code on this machine with:  ${BOLD}claude${RST}"
echo
echo "${DIM}Security notes:${RST}"
echo "${DIM} - Only devices logged into YOUR Tailscale account can reach this host.${RST}"
echo "${DIM} - No ports are exposed to the public internet.${RST}"
echo "${DIM} - Tighten who-can-SSH in your Tailscale admin console ACLs if you wish.${RST}"
