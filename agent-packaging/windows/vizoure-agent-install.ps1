#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Vizoure NMS Agent Installer for Windows
.DESCRIPTION
    Downloads and installs the Vizoure monitoring agent on Windows.
    Configures it to connect to your Vizoure NMS server.
.PARAMETER Server
    IP or hostname of your Vizoure NMS server
.PARAMETER Hostname
    Name to identify this machine in Vizoure NMS (defaults to computer name)
.PARAMETER ServerPort
    Vizoure server port (default: 10051)
.PARAMETER AgentPort
    Local agent port (default: 10050)
.EXAMPLE
    .\vizoure-agent-install.ps1 -Server 10.122.10.176
.EXAMPLE
    .\vizoure-agent-install.ps1 -Server vizoure.company.com -Hostname "Web-Server-01"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Server = "",

    [Parameter(Mandatory=$false)]
    [string]$Hostname = $env:COMPUTERNAME,

    [Parameter(Mandatory=$false)]
    [int]$ServerPort = 10051,

    [Parameter(Mandatory=$false)]
    [int]$AgentPort = 10050
)

# ─────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────
$AgentVersion  = "7.4.9"
$ZabbixVersion = "7.4"
$InstallDir    = "C:\Program Files\Vizoure Agent"
$ConfigFile    = "$InstallDir\conf\vizoure_agent.conf"
$ServiceName   = "Vizoure Agent"
$LogFile       = "$InstallDir\logs\vizoure_agent.log"
$DownloadUrl   = "https://cdn.zabbix.com/zabbix/binaries/stable/$ZabbixVersion/$AgentVersion/zabbix_agent-$AgentVersion-windows-amd64-openssl.msi"
$TempMSI       = "$env:TEMP\zabbix_agent_temp.msi"

# ─────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Vizoure NMS Agent Installer" -ForegroundColor Cyan
Write-Host "  Version: $AgentVersion" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────
# Get Server if not provided
# ─────────────────────────────────────────────
if ($Server -eq "") {
    $Server = Read-Host "Enter Vizoure NMS server IP or hostname"
    if ($Server -eq "") {
        Write-Host "ERROR: Server address is required." -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Server:   $Server" -ForegroundColor Green
Write-Host "  Hostname: $Hostname" -ForegroundColor Green
Write-Host "  Install:  $InstallDir" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────
# Step 1: Stop existing service if running
# ─────────────────────────────────────────────
Write-Host "[1/6] Checking existing installation..." -ForegroundColor Yellow

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $existingService) {
    Write-Host "  Stopping existing Vizoure Agent service..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Also check for Zabbix Agent service
$zabbixService = Get-Service -Name "Zabbix Agent" -ErrorAction SilentlyContinue
if ($null -ne $zabbixService) {
    Write-Host "  Stopping existing Zabbix Agent service..."
    Stop-Service -Name "Zabbix Agent" -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────
# Step 2: Download Zabbix Agent MSI
# ─────────────────────────────────────────────
Write-Host "[2/6] Downloading agent binaries..." -ForegroundColor Yellow

try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($DownloadUrl, $TempMSI)
    Write-Host "  Download complete." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Download failed: $_" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────
# Step 3: Silent install to temp location
# ─────────────────────────────────────────────
Write-Host "[3/6] Installing agent..." -ForegroundColor Yellow

$msiArgs = "/i `"$TempMSI`" /qn INSTALLDIR=`"$InstallDir`" SERVER=`"$Server`" SERVERACTIVE=`"$Server`" HOSTNAME=`"$Hostname`""
$result = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

if ($result.ExitCode -ne 0) {
    Write-Host "ERROR: MSI installation failed with exit code $($result.ExitCode)" -ForegroundColor Red
    exit 1
}

Write-Host "  Agent installed to $InstallDir" -ForegroundColor Green

# ─────────────────────────────────────────────
# Step 4: Create Vizoure config file
# ─────────────────────────────────────────────
Write-Host "[4/6] Configuring Vizoure Agent..." -ForegroundColor Yellow

# Create directories
New-Item -ItemType Directory -Path "$InstallDir\logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$InstallDir\conf" -Force | Out-Null

# Write Vizoure config
$configContent = @"
# Vizoure NMS Agent Configuration
# Generated by Vizoure Agent Installer

PidFile=$InstallDir\vizoure_agent.pid
LogFile=$LogFile
LogFileSize=10

Server=$Server
ServerActive=$Server`:$ServerPort
Hostname=$Hostname

ListenPort=$AgentPort

# Performance settings
Timeout=3
AllowRoot=0

# Include additional config files
# Include=$InstallDir\conf\*.conf
"@

Set-Content -Path $ConfigFile -Value $configContent -Encoding UTF8
Write-Host "  Config written to $ConfigFile" -ForegroundColor Green

# ─────────────────────────────────────────────
# Step 5: Rename service to Vizoure Agent
# ─────────────────────────────────────────────
Write-Host "[5/6] Configuring Windows service..." -ForegroundColor Yellow

# Find the installed Zabbix agent executable
$agentExe = Get-ChildItem -Path $InstallDir -Filter "zabbix_agentd.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($null -ne $agentExe) {
    # Stop the Zabbix Agent service installed by MSI
    Stop-Service -Name "Zabbix Agent" -Force -ErrorAction SilentlyContinue
    sc.exe delete "Zabbix Agent" | Out-Null
    Start-Sleep -Seconds 2

    # Create Vizoure Agent service pointing to the same executable
    $exePath = $agentExe.FullName
    sc.exe create $ServiceName binPath= "`"$exePath`" --config `"$ConfigFile`" --foreground" start= auto | Out-Null
    sc.exe description $ServiceName "Vizoure NMS monitoring agent. Collects system metrics and reports to Vizoure NMS server." | Out-Null
    Write-Host "  Service '$ServiceName' created." -ForegroundColor Green
} else {
    Write-Host "  WARNING: Could not find agent executable. Service may need manual configuration." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# Step 6: Start service and verify
# ─────────────────────────────────────────────
Write-Host "[6/6] Starting Vizoure Agent..." -ForegroundColor Yellow

try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    Start-Sleep -Seconds 3
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq "Running") {
        Write-Host "  Service is running." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Service status is $($service.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARNING: Could not start service: $_" -ForegroundColor Yellow
    Write-Host "  Try starting manually: Start-Service '$ServiceName'" -ForegroundColor Yellow
}

# Cleanup temp file
Remove-Item $TempMSI -Force -ErrorAction SilentlyContinue

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Vizoure Agent Installation Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Server:   $Server" -ForegroundColor Green
Write-Host "  Hostname: $Hostname" -ForegroundColor Green
Write-Host "  Service:  $ServiceName" -ForegroundColor Green
Write-Host "  Config:   $ConfigFile" -ForegroundColor Green
Write-Host "  Log:      $LogFile" -ForegroundColor Green
Write-Host ""
Write-Host "  Next: Add this host in Vizoure NMS:" -ForegroundColor White
Write-Host "  Data collection > Hosts > Create host" -ForegroundColor White
Write-Host "  Interface: Agent, IP: $(
    try { (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notmatch '^127'} | Select-Object -First 1).IPAddress } catch { 'this-machine-ip' }
), Port: $AgentPort" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Cyan
