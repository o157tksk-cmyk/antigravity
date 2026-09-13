# ==============================================================================
# Rocky Linux 9 Golden Image Creation Script (Fully Automated Kickstart)
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Error: Administrator privileges required."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$KsTemplate = Join-Path (Join-Path (Split-Path -Parent $ScriptDir) "scripts") "ks.cfg"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Error: Config file $ConfigFile not found."
    exit 1
}

$Config = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$MasterDir    = $Config.paths.masterDir
$IsoDir       = $Config.paths.isoDir
$VmDir        = $Config.paths.vmDir
$RockyIsoPath = $Config.paths.rockyIsoPath
$SwitchName   = $Config.network.switchName

$TemplateVmName = $Config.rockyTemplate.vmName
$TemplateVmPath = Join-Path $VmDir $TemplateVmName
$MasterVhdxPath = Join-Path $MasterDir "Rocky9-Golden.vhdx"
$OemDrvVhdx     = Join-Path $IsoDir "OEMDRV_Rocky.vhdx"

Write-Host "==================================================" -ForegroundColor Green
Write-Host " Rocky Linux 9 Golden Image Auto-Build Process" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host "Config file: $ConfigFile" -ForegroundColor Cyan
Write-Host "Template VM: $TemplateVmName" -ForegroundColor Cyan
Write-Host "Master VHDX: $MasterVhdxPath" -ForegroundColor Cyan

# 1. Directories
New-Item -ItemType Directory -Path $MasterDir -Force | Out-Null
New-Item -ItemType Directory -Path $IsoDir    -Force | Out-Null
New-Item -ItemType Directory -Path $VmDir     -Force | Out-Null

# 2. ISO check
if (-not (Test-Path $RockyIsoPath)) {
    Write-Error "Error: Rocky Linux ISO ($RockyIsoPath) not found."
    exit 1
}

# 3. Virtual Switch
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    Write-Host "[1/6] Creating Internal VMSwitch: $SwitchName..." -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    
    $NetAdapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$SwitchName*" -or $_.Name -like "*$SwitchName*" }
    if ($NetAdapter) {
        New-NetIPAddress -InterfaceIndex $NetAdapter.ifIndex -IPAddress $Config.network.gateway -PrefixLength $Config.network.prefixLength -ErrorAction SilentlyContinue | Out-Null
    }
}

# 4. Create OEMDRV VHDX
Write-Host "[2/6] Generating Kickstart OEMDRV disk ($OemDrvVhdx)..." -ForegroundColor Yellow
if (Test-Path $OemDrvVhdx) {
    Remove-Item $OemDrvVhdx -Force
}

$Vhd = New-VHD -Path $OemDrvVhdx -SizeBytes 64MB -Dynamic
$MountedDisk = Mount-VHD -Path $OemDrvVhdx -Passthru
$DiskNumber = $MountedDisk.DiskNumber

Initialize-Disk -Number $DiskNumber -PartitionStyle MBR -ErrorAction SilentlyContinue | Out-Null
$Partition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
$DriveLetter = "$($Partition.DriveLetter):"
Format-Volume -DriveLetter $Partition.DriveLetter -FileSystem FAT32 -NewFileSystemLabel "OEMDRV" -Confirm:$false | Out-Null

Copy-Item -Path $KsTemplate -Destination (Join-Path $DriveLetter "ks.cfg") -Force
Dismount-VHD -Path $OemDrvVhdx
Write-Host "[OK] OEMDRV disk created." -ForegroundColor Green

# 5. Create Template VM
Write-Host "[3/6] Creating Template VM: $TemplateVmName..." -ForegroundColor Yellow
if (Get-VM -Name $TemplateVmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $TemplateVmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $TemplateVmName -Force
}

if (Test-Path $TemplateVmPath) {
    Remove-Item -Path $TemplateVmPath -Recurse -Force
}
New-Item -ItemType Directory -Path $TemplateVmPath -Force | Out-Null

$VmDiskPath = Join-Path $TemplateVmPath "$TemplateVmName.vhdx"
New-VHD -Path $VmDiskPath -SizeBytes ($Config.rockyTemplate.diskSizeGB * 1GB) -Dynamic | Out-Null

$VM = New-VM -Name $TemplateVmName `
             -Generation 2 `
             -MemoryStartupBytes ($Config.rockyTemplate.ramMB * 1MB) `
             -VHDPath $VmDiskPath `
             -SwitchName $SwitchName `
             -Path $VmDir

Set-VMProcessor -VMName $TemplateVmName -Count $Config.rockyTemplate.cpuCount
Set-VMMemory -VMName $TemplateVmName -DynamicMemoryEnabled $false
Set-VMFirmware -VMName $TemplateVmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"

Add-VMScsiController -VMName $TemplateVmName -ErrorAction SilentlyContinue | Out-Null
$DvdDrive = Add-VMDvdDrive -VMName $TemplateVmName -Path $RockyIsoPath -Passthru
Add-VMHardDiskDrive -VMName $TemplateVmName -Path $OemDrvVhdx
Set-VMFirmware -VMName $TemplateVmName -FirstBootDevice $DvdDrive

# 6. Start Installation
Write-Host "[4/6] Starting $TemplateVmName for unattended installation..." -ForegroundColor Green
Start-VM -Name $TemplateVmName

Write-Host "Waiting for installation to finish and VM to power off..." -ForegroundColor Cyan

$Timeout = 900
$Elapsed = 0
while ((Get-VM -Name $TemplateVmName).State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) {
    Start-Sleep -Seconds 10
    $Elapsed += 10
    Write-Host "Elapsed: $($Elapsed)s..." -ForegroundColor Gray
    if ($Elapsed -ge $Timeout) {
        Write-Warning "Timeout waiting for VM to shut down."
        break
    }
}

if ((Get-VM -Name $TemplateVmName).State -eq [Microsoft.HyperV.PowerShell.VMState]::Off) {
    Write-Host "[5/6] OS Installation finished and VM powered off automatically!" -ForegroundColor Green
    
    $HddOEM = Get-VMHardDiskDrive -VMName $TemplateVmName | Where-Object { $_.Path -eq $OemDrvVhdx }
    if ($HddOEM) { Remove-VMHardDiskDrive $HddOEM }
    Set-VMDvdDrive -VMName $TemplateVmName -Path $null
    
    Write-Host "[6/6] Saving Master VHDX to $MasterVhdxPath..." -ForegroundColor Yellow
    Copy-Item -Path $VmDiskPath -Destination $MasterVhdxPath -Force
    
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host " Rocky Linux 9 Golden Image Created Successfully!" -ForegroundColor Green
    Write-Host " Template VM $TemplateVmName is kept in 'Off' state on Hyper-V." -ForegroundColor Cyan
    Write-Host " Master VHDX: $MasterVhdxPath" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Green
}
