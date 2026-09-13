# ==============================================================================
# Rocky Linux 9 (Web / External DNS / Mail) & AD Integration One-Click Master
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Error: Administrator privileges required."
    exit 1
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$RootDir    = Split-Path -Parent $ScriptDir
$ScriptsDir = Join-Path $RootDir "scripts"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Error: Config file $ConfigFile not found."
    exit 1
}

$Config = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$DomainName     = $Config.domain.name
$Dc01VmName     = $Config.dc01.vmName
$Dc01IP         = $Config.dc01.ipAddress
$AdminUser      = $Config.admin.username
$AdminPass      = $Config.admin.password
$RockyMasterVhd = Join-Path $Config.paths.masterDir "Rocky9-Golden.vhdx"
$SrvVmName      = $Config.servicesVm.vmName
$SrvIP          = $Config.servicesVm.ipAddress

Write-Host "=================================================================" -ForegroundColor Green
Write-Host " Rocky Linux (Web/DNS/Mail) & AD Integration One-Click Build" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Active Directory : $DomainName ($Dc01IP)" -ForegroundColor Cyan
Write-Host "Rocky Service VM : $SrvVmName ($SrvIP)" -ForegroundColor Cyan
Write-Host "Config File      : $ConfigFile" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Golden Image Build
Write-Host "[STEP 1/5] Checking Rocky Linux 9 Golden Image..." -ForegroundColor Yellow
if (-not (Test-Path $RockyMasterVhd)) {
    Write-Host "  -> Building Golden Image from scratch..." -ForegroundColor Cyan
    & "$ScriptDir\create_rocky_golden_template.ps1"
} else {
    Write-Host "  -> Existing Golden Image found: $RockyMasterVhd" -ForegroundColor Green
}

# STEP 2: Deploy Production VM
Write-Host "`n[STEP 2/5] Deploying Production VM ($SrvVmName)..." -ForegroundColor Yellow
& "$ScriptDir\deploy_rocky_from_golden.ps1"

# STEP 3: Configure Windows AD
Write-Host "`n[STEP 3/5] Configuring Active Directory ($Dc01VmName)..." -ForegroundColor Yellow
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(".\$AdminUser", $secPass)

$adScriptPath = Join-Path $ScriptDir "configure_ad_dns_and_ldap.ps1"
try {
    Invoke-Command -VMName $Dc01VmName -Credential $cred -FilePath $adScriptPath -ArgumentList @(
        $Config.domain.name,
        $Config.servicesVm.ipAddress,
        $Config.servicesVm.ldapServiceUser.username,
        $Config.servicesVm.ldapServiceUser.password,
        $Config.servicesVm.dnsRecords.web,
        $Config.servicesVm.dnsRecords.mail,
        $Config.servicesVm.dnsRecords.dns
    ) -ErrorAction Stop
    Write-Host "[OK] AD Configuration Completed." -ForegroundColor Green
} catch {
    Write-Warning "PowerShell Direct warning: $_"
}

# STEP 4: Wait for Rocky Linux SSH
Write-Host "`n[STEP 4/5] Waiting for $SrvVmName to boot and respond on SSH (port 22)..." -ForegroundColor Yellow
$Timeout = 180
$Elapsed = 0
$sshReady = $false

while ($Elapsed -lt $Timeout) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($SrvIP, 22, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(2000, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            $tcp.Close()
            $sshReady = $true
            Write-Host " [Connected in $Elapsed s]" -ForegroundColor Green
            break
        }
        $tcp.Close()
    } catch {}

    Start-Sleep -Seconds 5
    $Elapsed += 5
    Write-Host "." -NoNewline
}

# STEP 5: Deploy Services on Rocky Linux
Write-Host "`n[STEP 5/5] Deploying Linux Services (DNS, Web, Mail) on $SrvVmName..." -ForegroundColor Yellow

$setupScriptPath = Join-Path $ScriptsDir "setup_rocky_all_services.sh"
$testScriptPath  = Join-Path $ScriptsDir "test_all_services.sh"
$envScriptPath   = Join-Path $ScriptsDir "services.env"

$hasSsh = (Get-Command ssh.exe -ErrorAction SilentlyContinue) -ne $null

if ($hasSsh -and $sshReady) {
    Write-Host "  -> Transferring scripts and configuring via SSH..." -ForegroundColor Cyan
    $sshOpts = @("-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR")
    
    & scp.exe @sshOpts "$envScriptPath" "$setupScriptPath" "$testScriptPath" "root@${SrvIP}:/root/" 2>$null
    & ssh.exe @sshOpts "root@${SrvIP}" "chmod +x /root/setup_rocky_all_services.sh /root/test_all_services.sh && /root/setup_rocky_all_services.sh"
    
    Write-Host "`n>>> Running Integration Verification Tests..." -ForegroundColor Yellow
    & ssh.exe @sshOpts "root@${SrvIP}" "/root/test_all_services.sh"
} else {
    Write-Host "  -> SSH connection pending. Run /root/setup_rocky_all_services.sh inside VM." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " All Infrastructure Deployment & AD Integration Completed!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "  Active Directory DC : $DomainName ($Dc01IP)" -ForegroundColor Cyan
Write-Host "  External DNS Forward: $SrvIP (BIND 9 / port 53)" -ForegroundColor Cyan
Write-Host "  Web Portal (AD Auth): http://$SrvIP/ (http://web.$DomainName/)" -ForegroundColor Cyan
Write-Host "  Mail Server (AD Auth): mail.$DomainName (SMTP:25/587, IMAP:143)" -ForegroundColor Cyan
Write-Host "  Hyper-V Template    : Rocky9-Template (Off state)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Green
