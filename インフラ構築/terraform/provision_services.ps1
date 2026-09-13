# ==============================================================================
# Terraform Provisioner Script (AD Integration & Rocky Linux Services Setup)
# ==============================================================================

param (
    [string]$DomainName = "hogehoge.local",
    [string]$AdDcIp     = "192.168.10.10",
    [string]$SrvIp      = "192.168.10.20",
    [string]$LdapUser   = "svc_ldap",
    [string]$LdapPass   = "P@ssw0rd2022!",
    [string]$AdminUser  = "Administrator",
    [string]$AdminPass  = "P@ssw0rd2022!"
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$HypervDir  = Join-Path $RootDir "hyperv"
$ScriptsDir = Join-Path $RootDir "scripts"
$SshKeyPath = Join-Path (Join-Path $env:USERPROFILE ".ssh") "id_rsa"

Write-Host "=================================================================" -ForegroundColor Green
Write-Host " Terraform Provisioner: AD Integration & Linux Services Setup" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "AD DC: $DomainName ($AdDcIp)" -ForegroundColor Cyan
Write-Host "Target Linux IP: $SrvIp" -ForegroundColor Cyan

# 1. Configure Active Directory via PowerShell Direct
Write-Host "`n[1/3] Applying AD DNS & LDAP settings to Win2022-DC01..." -ForegroundColor Yellow
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(".\$AdminUser", $secPass)

$adScriptPath = Join-Path $HypervDir "configure_ad_dns_and_ldap.ps1"
try {
    Invoke-Command -VMName "Win2022-DC01" -Credential $cred -FilePath $adScriptPath -ArgumentList @(
        $DomainName,
        $SrvIp,
        $LdapUser,
        $LdapPass,
        "web",
        "mail",
        "ns"
    ) -ErrorAction Stop
    Write-Host "[OK] AD Configuration Completed." -ForegroundColor Green
} catch {
    Write-Warning "PowerShell Direct warning: $_"
}

# 2. Wait for Rocky Linux SSH
Write-Host "`n[2/3] Waiting for Rocky Linux ($SrvIp) SSH port (22)..." -ForegroundColor Yellow
$Timeout = 120
$Elapsed = 0
$sshReady = $false

while ($Elapsed -lt $Timeout) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($SrvIp, 22, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(2000, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($iar)
            $tcp.Close()
            $sshReady = $true
            Write-Host " [SSH Port 22 Open in $Elapsed s]" -ForegroundColor Green
            break
        }
        $tcp.Close()
    } catch {}

    Start-Sleep -Seconds 5
    $Elapsed += 5
    Write-Host "." -NoNewline
}

# 3. Transfer and execute setup on Rocky Linux
Write-Host "`n[3/3] Deploying BIND, Apache, Postfix, Dovecot on Rocky Linux..." -ForegroundColor Yellow

$setupScriptPath = Join-Path $ScriptsDir "setup_rocky_all_services.sh"
$testScriptPath  = Join-Path $ScriptsDir "test_all_services.sh"
$envScriptPath   = Join-Path $ScriptsDir "services.env"

# Update services.env
$envContent = @"
DOMAIN_NAME=$DomainName
DOMAIN_NETBIOS=HOGEHOGE
AD_DC_IP=$AdDcIp
SERVER_HOSTNAME=srv01
SERVER_IP=$SrvIp
GATEWAY_IP=192.168.10.1
PREFIX_LENGTH=24
SUBNET_CIDR=192.168.10.0/24
WEB_HOST_ALIAS=web
MAIL_HOST_ALIAS=mail
DNS_HOST_ALIAS=ns
EXT_FORWARDERS="8.8.8.8 1.1.1.1"
LDAP_USER=$LdapUser
LDAP_PASS=$LdapPass
ADMIN_USER=$AdminUser
ADMIN_PASS=$AdminPass
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envScriptPath, $envContent, $utf8NoBom)

Import-Module Posh-SSH -ErrorAction SilentlyContinue
$rootSec = ConvertTo-SecureString "P@ssw0rd2022!" -AsPlainText -Force
$rootCred = New-Object System.Management.Automation.PSCredential("root", $rootSec)

Write-Host "Connecting SSH session to Rocky Linux ($SrvIp)..." -ForegroundColor Cyan
Get-SSHSession | Remove-SSHSession -ErrorAction SilentlyContinue
$s = $null
for ($i = 0; $i -lt 10; $i++) {
    try {
        $s = New-SSHSession -ComputerName $SrvIp -Credential $rootCred -AcceptKey -ErrorAction Stop
        if ($s) { break }
    } catch {
        Start-Sleep -Seconds 3
    }
}

if ($s) {
    Write-Host "Transferring scripts to Rocky Linux..." -ForegroundColor Cyan
    Set-SCPItem -ComputerName $SrvIp -Credential $rootCred -Path $envScriptPath -Destination "/root/" -AcceptKey | Out-Null
    Set-SCPItem -ComputerName $SrvIp -Credential $rootCred -Path $setupScriptPath -Destination "/root/" -AcceptKey | Out-Null
    Set-SCPItem -ComputerName $SrvIp -Credential $rootCred -Path $testScriptPath -Destination "/root/" -AcceptKey | Out-Null

    Write-Host "Executing setup_rocky_all_services.sh on Rocky Linux..." -ForegroundColor Cyan
    $res = Invoke-SSHCommand -SessionId $s.SessionId -Command "chmod +x /root/*.sh && /root/setup_rocky_all_services.sh" -Timeout 600
    $res.Output | ForEach-Object { Write-Host $_ }

    Write-Host "`n>>> Running Integration Verification Tests..." -ForegroundColor Yellow
    $testRes = Invoke-SSHCommand -SessionId $s.SessionId -Command "/root/test_all_services.sh" -Timeout 120
    $testRes.Output | ForEach-Object { Write-Host $_ }

    Remove-SSHSession -SessionId $s.SessionId | Out-Null
} else {
    Write-Host "SSH not yet connected. Run /root/setup_rocky_all_services.sh inside VM." -ForegroundColor Yellow
}

Write-Host "`n[OK] Terraform Provisioning Completed!" -ForegroundColor Green
