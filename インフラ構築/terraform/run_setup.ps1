# ==============================================================================
# Rocky Linux 9 Setup & Verification Script (Posh-SSH)
# ==============================================================================

param (
    [string]$ServerIp = "192.168.10.20",
    [string]$Password = "P@ssw0rd2022!"
)

Import-Module Posh-SSH -ErrorAction SilentlyContinue

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir    = Split-Path -Parent $ScriptDir
$ScriptsDir = Join-Path $RootDir "scripts"

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("root", $secPass)

Write-Host "Connecting to Rocky Linux ($ServerIp) via SSH..." -ForegroundColor Cyan

Get-SSHSession | Remove-SSHSession -ErrorAction SilentlyContinue

$sshSession = New-SSHSession -ComputerName $ServerIp -Credential $cred -AcceptKey -ErrorAction Stop
Write-Host "[OK] SSH Connected!" -ForegroundColor Green

# 1. Upload scripts
Write-Host "Uploading setup scripts to Rocky Linux..." -ForegroundColor Cyan
Set-SCPItem -ComputerName $ServerIp -Credential $cred -Path (Join-Path $ScriptsDir "services.env") -Destination "/root/" -AcceptKey | Out-Null
Set-SCPItem -ComputerName $ServerIp -Credential $cred -Path (Join-Path $ScriptsDir "setup_rocky_all_services.sh") -Destination "/root/" -AcceptKey | Out-Null
Set-SCPItem -ComputerName $ServerIp -Credential $cred -Path (Join-Path $ScriptsDir "test_all_services.sh") -Destination "/root/" -AcceptKey | Out-Null
Write-Host "[OK] Scripts uploaded successfully." -ForegroundColor Green

# 2. Run setup script
Write-Host "`n[1/2] Executing setup_rocky_all_services.sh on Rocky Linux..." -ForegroundColor Yellow
$setupResult = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "chmod +x /root/*.sh && /root/setup_rocky_all_services.sh"
$setupResult.Output | ForEach-Object { Write-Host $_ }

# 3. Run test script
Write-Host "`n[2/2] Executing test_all_services.sh on Rocky Linux..." -ForegroundColor Yellow
$testResult = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command "/root/test_all_services.sh"
$testResult.Output | ForEach-Object { Write-Host $_ }

Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null

Write-Host "`n[OK] Rocky Linux Setup and Verification Completed!" -ForegroundColor Green
