# ==============================================================================
# Create and Start Rocky Linux VM from Golden VHDX
# ==============================================================================

param (
    [string]$VmName         = "Rocky9-AppSrv",
    [string]$VmsDir         = "C:\HyperV\VMs",
    [string]$MasterVhdxPath = "C:\HyperV\Master\Rocky9-Golden.vhdx",
    [string]$SwitchName     = "LabInternalSwitch",
    [int]$RamMb             = 4096,
    [int]$Cpus              = 2
)

Write-Host "[Terraform] Provisioning VM: $VmName..." -ForegroundColor Cyan

$vmDir  = Join-Path $VmsDir $VmName
$vmDisk = Join-Path $vmDir "$VmName.vhdx"
$ramBytes = [int64]$RamMb * 1024 * 1024

# 既存VMのクリーンアップ
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Write-Host "[Terraform] Removing existing VM $VmName..." -ForegroundColor Yellow
    Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $VmName -Force
}

if (Test-Path $vmDir) {
    Remove-Item -Path $vmDir -Recurse -Force
}
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

# マスターVHDX複製
Write-Host "[Terraform] Cloning Master VHDX..." -ForegroundColor Yellow
Copy-Item -Path $MasterVhdxPath -Destination $vmDisk -Force

# VM作成
Write-Host "[Terraform] Creating Generation 2 VM..." -ForegroundColor Yellow
$vm = New-VM -Name $VmName `
             -Generation 2 `
             -MemoryStartupBytes $ramBytes `
             -VHDPath $vmDisk `
             -SwitchName $SwitchName `
             -Path $VmsDir

Set-VMProcessor -VMName $VmName -Count $Cpus
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false
Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"

$hdd = Get-VMHardDiskDrive -VMName $VmName
Set-VMFirmware -VMName $VmName -FirstBootDevice $hdd

# ゲスト サービスを有効化 (Hyper-V ファイルコピー用)
Enable-VMIntegrationService -VMName $VmName -Name "Guest Service Interface", "ゲスト サービス" -ErrorAction SilentlyContinue | Out-Null

# VM起動
Write-Host "[Terraform] Starting VM $VmName..." -ForegroundColor Green
Start-VM -Name $VmName

Write-Host "[Terraform] VM $VmName started successfully!" -ForegroundColor Green
