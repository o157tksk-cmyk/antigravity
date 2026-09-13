# ==============================================================================
# Hyper-V 仮想マシン自動構築 & 無人ディスクアタッチスクリプト (PowerShell)
# 
# 目的: Windows Server 2022 / Rocky Linux 10 の VM 作成および autounattend.xml の自動アタッチ
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

# 1. 管理者権限のチェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。「管理者として実行」して再試行してください。"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Hyper-V 仮想マシン & 無人設定構築処理" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# 設定パラメーター
$IsoDir        = "C:\HyperV\ISO"
$VmDir         = "C:\HyperV\VMs"
$SwitchName    = "LabInternalSwitch"
$VhdUnattended = "C:\HyperV\ISO\Unattended.vhdx"

$WinIsoPath    = Join-Path $IsoDir "WindowsServer2022.iso"
$LinuxIsoPath  = Join-Path $IsoDir "RockyLinux10.iso"
if (-not (Test-Path $LinuxIsoPath)) {
    $LinuxIsoPath = Join-Path $IsoDir "RockyLinux9.iso"
}

$WinXml  = "c:\Users\tomoy\.gemini\antigravity\scratch\antigravity\インフラ構築\unattended\autounattend.xml"
$LinuxKs = "c:\Users\tomoy\.gemini\antigravity\scratch\antigravity\インフラ構築\unattended\ks.cfg"

# ディレクトリ作成
New-Item -ItemType Directory -Path $IsoDir -Force | Out-Null
New-Item -ItemType Directory -Path $VmDir -Force  | Out-Null

# 2. 内部仮想スイッチの作成
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    Write-Host "[1/5] 仮想スイッチ '$SwitchName' を作成中..." -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    
    $netAdapter = Get-NetAdapter -Name "*$SwitchName*" -ErrorAction SilentlyContinue
    if ($netAdapter) {
        New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress "192.168.10.1" -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    }
} else {
    Write-Host "[1/5] 仮想スイッチ '$SwitchName' は既に存在します。" -ForegroundColor Cyan
}

# 3. 無人応答ファイルディスク (Unattended.vhdx) の作成
Write-Host "[2/5] 無人応答ファイルディスク ($VhdUnattended) の作成中..." -ForegroundColor Yellow
if (Test-Path $VhdUnattended) {
    Dismount-VHD -Path $VhdUnattended -ErrorAction SilentlyContinue | Out-Null
    Remove-Item $VhdUnattended -Force -ErrorAction SilentlyContinue | Out-Null
}

$vhd = New-VHD -Path $VhdUnattended -SizeBytes 10MB -Dynamic
$disk = $vhd | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize
Format-Volume -Partition $disk -FileSystem FAT32 -NewFileSystemLabel "UNATTENDED" -Confirm:$false | Out-Null
$driveLetter = "$($disk.DriveLetter):"

if (Test-Path $WinXml) { Copy-Item $WinXml -Destination "$driveLetter\autounattend.xml" -Force }
if (Test-Path $LinuxKs) { Copy-Item $LinuxKs -Destination "$driveLetter\ks.cfg" -Force }
Dismount-VHD -Path $VhdUnattended | Out-Null

# 4. Windows Server 2022 VM (Win2022-DC) 作成 & アタッチ
$WinVmName = "Win2022-DC"
$WinVmPath = Join-Path $VmDir $WinVmName

if (-not (Get-VM -Name $WinVmName -ErrorAction SilentlyContinue)) {
    Write-Host "[3/5] 仮想マシン '$WinVmName' を作成中..." -ForegroundColor Yellow
    $WinVhdxPath = Join-Path $WinVmPath "$WinVmName.vhdx"
    New-Item -ItemType Directory -Path $WinVmPath -Force | Out-Null
    New-VHD -Path $WinVhdxPath -SizeBytes 60GB -Dynamic | Out-Null

    New-VM -Name $WinVmName -MemoryStartupBytes 4GB -Generation 2 -VHDPath $WinVhdxPath -Path $VmDir -SwitchName $SwitchName | Out-Null
    Set-VMMemory -VMName $WinVmName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB | Out-Null
    Set-VMProcessor -VMName $WinVmName -Count 2 | Out-Null
}

# ISO & 無人ディスクの割り当て
if (Test-Path $WinIsoPath) {
    $dvd = Get-VMDvdDrive -VMName $WinVmName
    if (-not $dvd) { Add-VMDvdDrive -VMName $WinVmName -Path $WinIsoPath | Out-Null } else { Set-VMDvdDrive -VMName $WinVmName -Path $WinIsoPath | Out-Null }
}
if (-not (Get-VMHardDiskDrive -VMName $WinVmName | Where-Object { $_.Path -eq $VhdUnattended })) {
    Add-VMHardDiskDrive -VMName $WinVmName -Path $VhdUnattended | Out-Null
}

# 5. Rocky Linux VM (Rocky10-Web) 作成 & アタッチ
$LinuxVmName = "Rocky10-Web"
$LinuxVmPath = Join-Path $VmDir $LinuxVmName

if (-not (Get-VM -Name $LinuxVmName -ErrorAction SilentlyContinue)) {
    Write-Host "[4/5] 仮想マシン '$LinuxVmName' を作成中..." -ForegroundColor Yellow
    $LinuxVhdxPath = Join-Path $LinuxVmPath "$LinuxVmName.vhdx"
    New-Item -ItemType Directory -Path $LinuxVmPath -Force | Out-Null
    New-VHD -Path $LinuxVhdxPath -SizeBytes 30GB -Dynamic | Out-Null

    New-VM -Name $LinuxVmName -MemoryStartupBytes 2GB -Generation 2 -VHDPath $LinuxVmPath -Path $VmDir -SwitchName $SwitchName | Out-Null
    Set-VMMemory -VMName $LinuxVmName -DynamicMemoryEnabled $true -MinimumBytes 1GB -MaximumBytes 4GB | Out-Null
    Set-VMProcessor -VMName $LinuxVmName -Count 2 | Out-Null
    Set-VMFirmware -VMName $LinuxVmName -SecureBootTemplate "MicrosoftUEFICertificateAuthority" | Out-Null
}

if (Test-Path $LinuxIsoPath) {
    $dvd = Get-VMDvdDrive -VMName $LinuxVmName
    if (-not $dvd) { Add-VMDvdDrive -VMName $LinuxVmName -Path $LinuxIsoPath | Out-Null } else { Set-VMDvdDrive -VMName $LinuxVmName -Path $LinuxIsoPath | Out-Null }
}
if (-not (Get-VMHardDiskDrive -VMName $LinuxVmName | Where-Object { $_.Path -eq $VhdUnattended })) {
    Add-VMHardDiskDrive -VMName $LinuxVmName -Path $VhdUnattended -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host "  [5/5] 無人ディスク割り当て & 仮想マシン再設定完了" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
