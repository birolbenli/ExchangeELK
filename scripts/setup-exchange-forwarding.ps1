# Exchange Server Log Forwarding Setup Script
# Run this script on each Exchange Server to set up log collection
#
#   .\setup-exchange-forwarding.ps1 -ELKServerIP "10.11.12.19" -InstallFilebeatAgent
#   .\setup-exchange-forwarding.ps1 -ELKServerIP "10.11.12.19" -ResetRegistry
#     → Filebeat registry silinir, ignore_older (48s) içindeki dosyalar yeniden okunur.
#       5044 uzun süre refuse olduktan / domain join reboot sonrası takılırsa kullanın.

param(
    [Parameter(Mandatory=$true)]
    [string]$ELKServerIP,
    
    [Parameter(Mandatory=$false)]
    [string]$LogSharePath = "\\$ELKServerIP\exchange-logs",
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallFilebeatAgent,

    [Parameter(Mandatory=$false)]
    [switch]$ResetRegistry
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
    "MessageTracking" = Join-Path $ExchangePath "Logging\MessageTracking"
    "IIS"             = "C:\inetpub\logs\LogFiles"
    "HttpProxy"       = Join-Path $ExchangePath "Logging\HttpProxy"
    "MapiHttp"        = Join-Path $ExchangePath "Logging\MapiHttp"
    "SMTP Receive"    = Join-Path $ExchangePath "Logging\ProtocolLog\SmtpReceive"
    "SMTP Send"       = Join-Path $ExchangePath "Logging\ProtocolLog\SmtpSend"
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
        
        # Create Filebeat configuration (UTF-8 BOM'suz — YAML parse kırılmasın)
        $ExBase = $ExchangePath.TrimEnd('\')
        $FilebeatConfig = @"
queue.disk:
  max_size: 2GB
  path: C:\ProgramData\filebeat\queue

filebeat.inputs:

- type: filestream
  enabled: true
  id: exchange-message-tracking
  take_over: true
  paths:
    - '$ExBase\Logging\MessageTracking\*.LOG'
    - '$ExBase\Logging\MessageTracking\*.log'
    - 'Z:\MessageTrackingLogs\*.LOG'
    - 'Z:\MessageTrackingLogs\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["MessageTracking"]
  fields:
    log_type: message-tracking
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 10s
  close.on_state_change.inactive: 5m
  close.on_state_change.renamed: true
  file_identity.path: ~
  buffer_size: 32768

- type: filestream
  enabled: true
  id: exchange-iis
  take_over: true
  paths:
    - 'C:\inetpub\logs\LogFiles\W3SVC*\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["ExchangeIIS"]
  fields:
    log_type: iis
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 15s
  close.on_state_change.inactive: 5m
  file_identity.path: ~
  buffer_size: 32768

- type: filestream
  enabled: true
  id: exchange-httpproxy
  take_over: true
  paths:
    - '$ExBase\Logging\HttpProxy\*\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["HttpProxy"]
  fields:
    log_type: httpproxy
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 30s
  close.on_state_change.inactive: 10m
  file_identity.path: ~
  buffer_size: 65536

- type: filestream
  enabled: true
  id: exchange-mapihttp
  take_over: true
  paths:
    - '$ExBase\Logging\MapiHttp\*\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["MapiHttp"]
  fields:
    log_type: mapihttp
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 30s
  close.on_state_change.inactive: 10m
  file_identity.path: ~
  buffer_size: 65536

- type: filestream
  enabled: true
  id: exchange-smtp-receive
  take_over: true
  paths:
    - '$ExBase\Logging\ProtocolLog\SmtpReceive\*.log'
    - 'Z:\SmtpReceive\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["SmtpReceive"]
  fields:
    log_type: smtp-receive
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 15s
  close.on_state_change.inactive: 5m
  file_identity.path: ~
  buffer_size: 32768

- type: filestream
  enabled: true
  id: exchange-smtp-send
  take_over: true
  paths:
    - '$ExBase\Logging\ProtocolLog\SmtpSend\*.log'
    - 'Z:\SmtpSend\*.log'
  encoding: utf-8
  exclude_lines: ['^#']
  tags: ["SmtpSend"]
  fields:
    log_type: smtp-send
  fields_under_root: true
  ignore_older: 48h
  clean_inactive: 72h
  clean_removed: false
  prospector.scanner.check_interval: 15s
  close.on_state_change.inactive: 5m
  file_identity.path: ~
  buffer_size: 32768

path.data: C:\ProgramData\filebeat
filebeat.registry.path: C:\ProgramData\filebeat\registry
filebeat.registry.flush: 5s
filebeat.shutdown_timeout: 30s

processors:
  - add_host_metadata: ~
  - drop_fields:
      fields: ["ecs", "input.type", "log.offset"]
      ignore_missing: true

output.logstash:
  hosts: ["${ELKServerIP}:5044"]
  compression_level: 3
  bulk_max_size: 1024
  pipelining: 0
  ttl: 60s
  timeout: 30s
  max_retries: -1
  backoff.init: 1s
  backoff.max: 60s
  slow_start: true
  loadbalance: false
  ssl.enabled: false

logging.level: info
logging.to_files: true
logging.files:
  path: C:\ProgramData\filebeat\logs
  name: filebeat
  keepfiles: 7
"@

        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText("$InstallPath\filebeat.yml", $FilebeatConfig, $utf8NoBom)
        
        # Install as Windows service
        Set-Location $InstallPath
        PowerShell.exe -ExecutionPolicy UnRestricted -File .\install-service-filebeat.ps1
        
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

# 5044 uzun süre refuse / domain join reboot sonrası takılan registry
function Reset-FilebeatRegistry {
    Write-Host "Filebeat registry sifirlaniyor (ignore_older=48h yeniden okunur)..." -ForegroundColor Yellow
    $svc = Get-Service -Name "filebeat" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Stop-Service filebeat -Force
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $paths = @(
        "C:\ProgramData\filebeat\registry",
        "C:\ProgramData\filebeat\data",
        "C:\Program Files\Filebeat\data"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $bak = "$p.bak-$stamp"
            Rename-Item -Path $p -NewName (Split-Path $bak -Leaf)
            Write-Host "  $p -> $bak" -ForegroundColor Yellow
        }
    }
    New-Item -ItemType Directory -Path "C:\ProgramData\filebeat\registry" -Force | Out-Null
    if ($svc) {
        Start-Service filebeat
        Write-Host "Filebeat yeniden baslatildi." -ForegroundColor Green
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

if ($ResetRegistry) {
    Reset-FilebeatRegistry
}

# Setup Windows Event Log forwarding (yalnızca kurulumda)
if ($InstallFilebeatAgent -and -not $ResetRegistry) {
    $eventLogSetup = Setup-EventLogForwarding
}

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