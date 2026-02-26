# Exchange Server Log Forwarding Setup Script
# Run this script on each Exchange Server to set up log collection

param(
    [Parameter(Mandatory=$true)]
    [string]$ELKServerIP,
    
    [Parameter(Mandatory=$false)]
    [string]$LogSharePath = "\\$ELKServerIP\exchange-logs",
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallFilebeatAgent
)

Write-Host "Exchange Server Log Forwarding Setup" -ForegroundColor Green
Write-Host "Target ELK Server: $ELKServerIP" -ForegroundColor Yellow

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges!" -ForegroundColor Red
    exit 1
}

# Get Exchange installation path
$ExchangePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup" -Name "MsiInstallPath").MsiInstallPath

if (!$ExchangePath) {
    Write-Host "Exchange Server not found on this system!" -ForegroundColor Red
    exit 1
}

Write-Host "Exchange Server found at: $ExchangePath" -ForegroundColor Green

# Define log directories (Z: sürücüsüne taşınan loglar dahil)
$LogDirectories = @{
    "MessageTracking" = "Z:\MessageTrackingLogs"
    "IIS"             = "C:\inetpub\logs\LogFiles"
    "HttpProxy"       = "$ExchangePath\Logging\HttpProxy"
    "MapiHttp"        = "$ExchangePath\Logging\MapiHttp"
    "SMTP Receive"    = "Z:\SmtpReceive"
    "SMTP Send"       = "Z:\SmtpSend"
    "Connectivity"    = "Z:\ConnectivityLogs"
}

# Function to create network share access
function Setup-NetworkShare {
    param([string]$SharePath)
    
    try {
        Write-Host "Setting up network share access to $SharePath..." -ForegroundColor Yellow
        
        # Test connection to ELK server
        $pingResult = Test-NetConnection -ComputerName $ELKServerIP -Port 22 -WarningAction SilentlyContinue
        if ($pingResult.TcpTestSucceeded) {
            Write-Host "Connection to ELK server successful" -ForegroundColor Green
        } else {
            Write-Host "Cannot connect to ELK server at $ELKServerIP" -ForegroundColor Red
        }
        
        return $true
    }
    catch {
        Write-Host "Error setting up network share: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to install and configure Filebeat
function Install-FilebeatAgent {
    Write-Host "Installing Filebeat agent..." -ForegroundColor Yellow
    
    $FilebeatUrl = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.11.1-windows-x86_64.zip"
    $DownloadPath = "$env:TEMP\filebeat.zip"
    $InstallPath = "C:\Program Files\Filebeat"
    
    try {
        # Download Filebeat
        Invoke-WebRequest -Uri $FilebeatUrl -OutFile $DownloadPath
        
        # Extract to install directory
        if (Test-Path $InstallPath) {
            Remove-Item $InstallPath -Recurse -Force
        }
        Expand-Archive -Path $DownloadPath -DestinationPath "C:\Program Files\"
        
        # Rename directory
        $ExtractedDir = Get-ChildItem "C:\Program Files\filebeat-*" | Select-Object -First 1
        Rename-Item $ExtractedDir.FullName $InstallPath
        
        # Create Filebeat configuration
        $FilebeatConfig = @"
filebeat.inputs:

# Message Tracking Logs (Z: sürücüsü)
- type: log
  enabled: true
  id: exchange-message-tracking
  paths:
    - 'Z:\MessageTrackingLogs\*.log'
  tags: ["MessageTracking"]
  fields_under_root: true
  scan_frequency: 15s
  close_inactive: 5m

# IIS W3C Logs (X-Forwarded-For aktif edilmistir)
- type: log
  enabled: true
  id: exchange-iis
  paths:
    - 'C:\inetpub\logs\LogFiles\W3SVC*\*.log'
  tags: ["ExchangeIIS"]
  fields_under_root: true
  scan_frequency: 15s
  close_inactive: 5m

# HttpProxy Protocol Logs
- type: log
  enabled: true
  id: exchange-httpproxy
  paths:
    - 'C:\Program Files\Microsoft\Exchange Server\V15\Logging\HttpProxy\*\*.log'
  tags: ["HttpProxy"]
  fields_under_root: true
  scan_frequency: 30s
  close_inactive: 10m

# MAPI HTTP Logs
- type: log
  enabled: true
  id: exchange-mapihttp
  paths:
    - 'C:\Program Files\Microsoft\Exchange Server\V15\Logging\MapiHttp\*\*.log'
  tags: ["MapiHttp"]
  fields_under_root: true
  scan_frequency: 30s
  close_inactive: 10m

# SMTP Receive Logs (Z: sürücüsü)
- type: log
  enabled: true
  id: exchange-smtp-receive
  paths:
    - 'Z:\SmtpReceive\*.log'
  tags: ["SmtpReceive"]
  fields_under_root: true
  scan_frequency: 15s
  close_inactive: 5m

# SMTP Send Logs (Z: sürücüsü)
- type: log
  enabled: true
  id: exchange-smtp-send
  paths:
    - 'Z:\SmtpSend\*.log'
  tags: ["SmtpSend"]
  fields_under_root: true
  scan_frequency: 15s
  close_inactive: 5m

processors:
  - add_host_metadata: ~
  - drop_fields:
      fields: ["ecs", "input.type", "log.offset"]
      ignore_missing: true

output.logstash:
  hosts: ["${ELKServerIP}:5044"]
  compression_level: 3
  bulk_max_size: 1024

logging.level: warning
logging.to_files: true
logging.files:
  path: C:\ProgramData\filebeat\logs
  name: filebeat
  keepfiles: 7
"@
        
        $FilebeatConfig | Out-File -FilePath "$InstallPath\filebeat.yml" -Encoding UTF8
        
        # Install as Windows service
        Set-Location $InstallPath
        & .\filebeat.exe --path.config $InstallPath install
        
        # Start service
        Start-Service filebeat
        
        Write-Host "Filebeat installed and started successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error installing Filebeat: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to configure Windows Event Log forwarding
function Setup-EventLogForwarding {
    Write-Host "Configuring Windows Event Log forwarding..." -ForegroundColor Yellow
    
    try {
        # Enable Windows Remote Management
        winrm quickconfig -force
        
        # Configure event log forwarding
        wecutil qc /force
        
        Write-Host "Event log forwarding configured" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Error configuring event log forwarding: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
Write-Host "Starting Exchange log forwarding setup..." -ForegroundColor Green

# Setup network connectivity
$shareSetup = Setup-NetworkShare -SharePath $LogSharePath

# Install Filebeat if requested
if ($InstallFilebeatAgent) {
    $filebeatSetup = Install-FilebeatAgent
}

# Setup Windows Event Log forwarding
$eventLogSetup = Setup-EventLogForwarding

# Display log directory information
Write-Host "`nExchange Log Directories:" -ForegroundColor Yellow
foreach ($key in $LogDirectories.Keys) {
    $path = $LogDirectories[$key]
    if (Test-Path $path) {
        Write-Host "  $key : $path [EXISTS]" -ForegroundColor Green
    } else {
        Write-Host "  $key : $path [NOT FOUND]" -ForegroundColor Red
    }
}

# Create monitoring script
$MonitoringScript = @"
# Exchange Log Monitoring Script
# Check log file sizes and Filebeat status

`$LogDirs = @(
    "C:\Program Files\Microsoft\Exchange Server\V15\Logging\MessageTracking"
    "C:\inetpub\logs\LogFiles"
    "C:\Program Files\Microsoft\Exchange Server\V15\Logging\SmtpSend"
    "C:\Program Files\Microsoft\Exchange Server\V15\Logging\TransportService"
)

Write-Host "Exchange Log Monitoring Report - $(Get-Date)" -ForegroundColor Green

foreach (`$dir in `$LogDirs) {
    if (Test-Path `$dir) {
        `$files = Get-ChildItem `$dir -Recurse -File | Measure-Object -Property Length -Sum
        `$size = [math]::Round(`$files.Sum / 1MB, 2)
        Write-Host "`$dir : `$(`$files.Count) files, `$size MB" -ForegroundColor Yellow
    }
}

# Check Filebeat service status
`$filebeatService = Get-Service -Name "filebeat" -ErrorAction SilentlyContinue
if (`$filebeatService) {
    if (`$filebeatService.Status -eq "Running") {
        Write-Host "Filebeat Service: Running" -ForegroundColor Green
    } else {
        Write-Host "Filebeat Service: `$(`$filebeatService.Status)" -ForegroundColor Red
    }
}
"@

$MonitoringScript | Out-File -FilePath "C:\ExchangeLogMonitoring.ps1" -Encoding UTF8

Write-Host "`nSetup completed!" -ForegroundColor Green
Write-Host "Monitoring script created at: C:\ExchangeLogMonitoring.ps1" -ForegroundColor Yellow
Write-Host "`nTo monitor logs, run: PowerShell -ExecutionPolicy Bypass -File C:\ExchangeLogMonitoring.ps1" -ForegroundColor Cyan