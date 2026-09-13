# ==============================================================================
# Rocky Linux 9 Production VM (Rocky9-AppSrv) Fast Deploy Script
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Error: Administrator privileges required."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Error: Config file $ConfigFile not found."
    exit 1
}

$Config = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$MasterDir      = $Config.paths.masterDir
$VmDir          = $Config.paths.vmDir
$SwitchName     = $Config.network.switchName
$MasterVhdxPath = Join-Path $MasterDir "Rocky9-Golden.vhdx"

$SrvVmName      = $Config.servicesVm.vmName
$SrvVmPath      = Join-Path $VmDir $SrvVmName
$SrvVhdxPath    = Join-Path $SrvVmPath "$SrvVmName.vhdx"

Write-Host "==================================================" -ForegroundColor Green
Write-Host " Rocky Linux 9 Production VM Fast Deployment" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host "Target VM: $SrvVmName" -ForegroundColor Cyan
Write-Host "IP: $($Config.servicesVm.ipAddress)" -ForegroundColor Cyan
Write-Host "Master Image: $MasterVhdxPath" -ForegroundColor Cyan

# 1. Master Image Check
if (-not (Test-Path $MasterVhdxPath)) {
    Write-Error "Error: Master image ($MasterVhdxPath) not found."
    exit 1
}

# 2. Cleanup existing VM
if (Get-VM -Name $SrvVmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $SrvVmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $SrvVmName -Force
}

if (Test-Path $SrvVmPath) {
    Remove-Item -Path $SrvVmPath -Recurse -Force
}
New-Item -ItemType Directory -Path $SrvVmPath -Force | Out-Null

# 3. Clone Master VHDX
Write-Host "[1/3] Cloning Master VHDX..." -ForegroundColor Yellow
Copy-Item -Path $MasterVhdxPath -Destination $SrvVhdxPath -Force

# 4. Create VM
Write-Host "[2/3] Creating Virtual Machine $SrvVmName..." -ForegroundColor Yellow
$VM = New-VM -Name $SrvVmName `
             -Generation 2 `
             -MemoryStartupBytes ($Config.servicesVm.ramMB * 1MB) `
             -VHDPath $SrvVhdxPath `
             -SwitchName $SwitchName `
             -Path $VmDir

Set-VMProcessor -VMName $SrvVmName -Count $Config.servicesVm.cpuCount
Set-VMMemory -VMName $SrvVmName -DynamicMemoryEnabled $false
Set-VMFirmware -VMName $SrvVmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"

# First boot device: Hard Disk
$Hdd = Get-VMHardDiskDrive -VMName $SrvVmName
Set-VMFirmware -VMName $SrvVmName -FirstBootDevice $Hdd

# 5. Generate services.env
$EnvFile = Join-Path (Join-Path (Split-Path -Parent $ScriptDir) "scripts") "services.env"
$EnvContent = @"
DOMAIN_NAME=$($Config.domain.name)
DOMAIN_NETBIOS=$($Config.domain.netbios)
AD_DC_IP=$($Config.dc01.ipAddress)
SERVER_HOSTNAME=$($Config.servicesVm.hostname)
SERVER_IP=$($Config.servicesVm.ipAddress)
GATEWAY_IP=$($Config.network.gateway)
PREFIX_LENGTH=$($Config.network.prefixLength)
SUBNET_CIDR=$($Config.network.subnet)
WEB_HOST_ALIAS=$($Config.servicesVm.dnsRecords.web)
MAIL_HOST_ALIAS=$($Config.servicesVm.dnsRecords.mail)
DNS_HOST_ALIAS=$($Config.servicesVm.dnsRecords.dns)
EXT_FORWARDERS="$($Config.servicesVm.externalDnsForwarders -join ' ')"
LDAP_USER=$($Config.servicesVm.ldapServiceUser.username)
LDAP_PASS=$($Config.servicesVm.ldapServiceUser.password)
ADMIN_USER=$($Config.admin.username)
ADMIN_PASS=$($Config.admin.password)
"@
Set-Content -Path $EnvFile -Value $EnvContent -Encoding UTF8

# 6. Start VM
Write-Host "[3/3] Starting Virtual Machine $SrvVmName..." -ForegroundColor Green
Start-VM -Name $SrvVmName

Write-Host "Production VM $SrvVmName deployed successfully!" -ForegroundColor Green
