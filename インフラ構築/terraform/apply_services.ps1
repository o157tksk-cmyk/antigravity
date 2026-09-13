Import-Module Posh-SSH -ErrorAction SilentlyContinue

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ScriptsDir = Join-Path $RootDir "scripts"

$ip = "192.168.10.20"
$password = "P@ssw0rd2022!"
$secPass = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $secPass)

# 1. services.env を BOM なし UTF-8 で生成
$envPath = Join-Path $ScriptsDir "services.env"
$envContent = @"
DOMAIN_NAME=hogehoge.local
DOMAIN_NETBIOS=HOGEHOGE
AD_DC_IP=192.168.10.10
SERVER_HOSTNAME=srv01
SERVER_IP=192.168.10.20
GATEWAY_IP=192.168.10.1
PREFIX_LENGTH=24
SUBNET_CIDR=192.168.10.0/24
WEB_HOST_ALIAS=web
MAIL_HOST_ALIAS=mail
DNS_HOST_ALIAS=ns
EXT_FORWARDERS="8.8.8.8 1.1.1.1"
LDAP_USER=svc_ldap
LDAP_PASS=P@ssw0rd2022!
ADMIN_USER=Administrator
ADMIN_PASS=P@ssw0rd2022!
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envPath, $envContent, $utf8NoBom)

Write-Host "Connecting to Rocky Linux ($ip)..." -ForegroundColor Cyan

Get-SSHSession | Remove-SSHSession -ErrorAction SilentlyContinue

$s = $null
for ($i = 0; $i -lt 5; $i++) {
    try {
        $s = New-SSHSession -ComputerName $ip -Credential $cred -AcceptKey -ErrorAction Stop
        if ($s) { break }
    } catch {
        Write-Host "Retry connection ($i/5)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}

if (-not $s) {
    Write-Error "Failed to connect to Rocky Linux via SSH."
    exit 1
}

Write-Host "[OK] SSH Connected!" -ForegroundColor Green

Write-Host "Uploading setup scripts to Rocky Linux..." -ForegroundColor Cyan
Set-SCPItem -ComputerName $ip -Credential $cred -Path $envPath -Destination "/root/" -AcceptKey | Out-Null
Set-SCPItem -ComputerName $ip -Credential $cred -Path (Join-Path $ScriptsDir "setup_rocky_all_services.sh") -Destination "/root/" -AcceptKey | Out-Null
Set-SCPItem -ComputerName $ip -Credential $cred -Path (Join-Path $ScriptsDir "test_all_services.sh") -Destination "/root/" -AcceptKey | Out-Null
Write-Host "[OK] Scripts uploaded successfully." -ForegroundColor Green

Write-Host "`n[1/2] Executing setup_rocky_all_services.sh on Rocky Linux (Timeout: 600s)..." -ForegroundColor Yellow
$res = Invoke-SSHCommand -SessionId $s.SessionId -Command "chmod +x /root/*.sh && /root/setup_rocky_all_services.sh" -Timeout 600
$res.Output | ForEach-Object { Write-Host $_ }

Write-Host "`n[2/2] Executing test_all_services.sh on Rocky Linux..." -ForegroundColor Yellow
$testRes = Invoke-SSHCommand -SessionId $s.SessionId -Command "/root/test_all_services.sh" -Timeout 120
$testRes.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $s.SessionId | Out-Null

Write-Host "`n[OK] All Services Configured and Verified Successfully!" -ForegroundColor Green
