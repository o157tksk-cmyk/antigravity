# ==============================================================================
# ホストから PowerShell Direct 経由で AD に設定を投入するスクリプト
# ==============================================================================

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$Config     = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$secPass = ConvertTo-SecureString $Config.admin.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(".\$($Config.admin.username)", $secPass)

$adScriptPath = Join-Path $ScriptDir "configure_ad_dns_and_ldap.ps1"

Write-Host "PowerShell Direct 経由で $($Config.dc01.vmName) へスクリプトを投入中..." -ForegroundColor Cyan

Invoke-Command -VMName $Config.dc01.vmName -Credential $cred -FilePath $adScriptPath -ArgumentList @(
    $Config.domain.name,
    $Config.servicesVm.ipAddress,
    $Config.servicesVm.ldapServiceUser.username,
    $Config.servicesVm.ldapServiceUser.password,
    $Config.servicesVm.dnsRecords.web,
    $Config.servicesVm.dnsRecords.mail,
    $Config.servicesVm.dnsRecords.dns
)
