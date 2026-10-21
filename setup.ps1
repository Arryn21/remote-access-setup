<#
    setup.ps1 — Remote access setup for Windows

    Sets up secure remote SSH access to THIS machine from anywhere, using
    Tailscale (a WireGuard mesh VPN) so it works behind any NAT/firewall
    without opening ports or exposing SSH to the public internet.

    What it does:
      1. Installs Tailscale (via winget, else the official MSI).
      2. Installs & starts the Windows OpenSSH Server.
      3. Brings up Tailscale with Tailscale SSH enabled and prints the
         login URL so you can attach this device to YOUR Tailscale account.
      4. Prints the address you use to connect from your other machine.

    Run ONLY on machines you own or are explicitly authorized to administer.

    Usage (in an *elevated* PowerShell — "Run as administrator"):
      Set-ExecutionPolicy -Scope Process Bypass -Force
      irm https://raw.githubusercontent.com/Arryn21/remote-access-setup/main/setup.ps1 | iex
      # or, after cloning:
      .\setup.ps1
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  ok $m" -ForegroundColor Green }
function Warn($m) { Write-Host "warn $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host " err $m" -ForegroundColor Red; exit 1 }
function Step($m) { Write-Host "`n$m" -ForegroundColor White -BackgroundColor DarkBlue }

# ---- must be elevated ------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "Please run this in an elevated PowerShell (right-click > Run as administrator)."
}

Step "Remote access setup  (platform: windows)"

# ===========================================================================
# 1. Install Tailscale
# ===========================================================================
Step "1/4  Install Tailscale"
function Test-Tailscale { return [bool](Get-Command tailscale -ErrorAction SilentlyContinue) }

if (Test-Tailscale) {
    Ok "Tailscale already installed"
} else {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Info "Installing Tailscale via winget..."
        winget install --id Tailscale.Tailscale --silent --accept-source-agreements --accept-package-agreements
    } else {
        Info "winget not found; downloading the official Tailscale MSI..."
        $msi = Join-Path $env:TEMP "tailscale-setup.msi"
        Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-latest.msi" -OutFile $msi
        Info "Running the installer (silent)..."
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait
        Remove-Item $msi -ErrorAction SilentlyContinue
    }
    # The freshly-installed tailscale.exe may not be on PATH in this session.
    $tsDir = Join-Path $env:ProgramFiles "Tailscale"
    if (Test-Path $tsDir) { $env:Path = "$env:Path;$tsDir" }
    if (Test-Tailscale) { Ok "Tailscale installed" } else { Die "Tailscale install did not complete. Reboot or re-run." }
}

# ===========================================================================
# 2. Install & start the OpenSSH Server
# ===========================================================================
Step "2/4  Enable SSH server"
Info "Checking the Windows OpenSSH Server capability..."
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server* -ErrorAction SilentlyContinue
if ($cap -and $cap.State -ne 'Installed') {
    Info "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
Ok "OpenSSH Server present"

Info "Setting sshd to start automatically and starting it..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Ok "sshd running"

# Allow SSH through the firewall (usually created by the capability, but be sure).
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    Ok "Firewall rule for SSH added"
}

# ===========================================================================
# 3. Bring up Tailscale (with Tailscale SSH)
# ===========================================================================
Step "3/4  Connect to your tailnet"
Info "Bringing up Tailscale with Tailscale SSH enabled..."
Write-Host "If this device isn't logged in yet, a browser login window/URL will appear." -ForegroundColor DarkGray
Write-Host "Open it and approve the device on YOUR Tailscale account." -ForegroundColor DarkGray
& tailscale up --ssh
if ($LASTEXITCODE -ne 0) { Die "tailscale up failed. Re-run:  tailscale up --ssh" }
Ok "Tailscale is up"

# ===========================================================================
# 4. Report connection details
# ===========================================================================
Step "4/4  Done — how to connect"
$tsIp = (& tailscale ip -4 2>$null | Select-Object -First 1)
$tsHost = $null
try {
    $status = (& tailscale status --json 2>$null | ConvertFrom-Json)
    $tsHost = ($status.Self.DNSName).TrimEnd('.')
} catch {}
$userName = $env:USERNAME

Write-Host ""
Ok "This machine is reachable on your tailnet."
Write-Host "   From your other computer (also signed into your Tailscale account):" -ForegroundColor White
if ($tsHost) { Write-Host "     ssh $userName@$tsHost" }
if ($tsIp)   { Write-Host "     ssh $userName@$tsIp    (by IP)" }
if (-not $tsHost -and -not $tsIp) {
    Warn "Could not read the Tailscale address yet. Run 'tailscale status' once login completes."
}
Write-Host ""
Write-Host "   Then run Claude Code on this machine with:  claude" -ForegroundColor White
Write-Host ""
Write-Host "Security notes:" -ForegroundColor DarkGray
Write-Host " - Only devices logged into YOUR Tailscale account can reach this host." -ForegroundColor DarkGray
Write-Host " - No ports are exposed to the public internet." -ForegroundColor DarkGray
Write-Host " - Tighten who-can-SSH in your Tailscale admin console ACLs if you wish." -ForegroundColor DarkGray
