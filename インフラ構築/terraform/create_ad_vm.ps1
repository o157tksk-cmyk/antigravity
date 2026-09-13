# ==============================================================================
# Create AD Domain Controller VM from Windows Server 2022 Golden VHDX
# ==============================================================================

param (
    [string]$VmName,
    [string]$VmsDir = "C:\HyperV\VMs",
    [string]$MasterVhdxPath = "C:\HyperV\Master\Win2022-GoldenImage.vhdx",
    [string]$SwitchName = "LabInternalSwitch",
    [int]$RamMb = 4096,
    [int]$Cpus = 2
)

Write-Host "[Terraform] Checking AD VM: $VmName..." -ForegroundColor Cyan

$VmPath = Join-Path $VmsDir $VmName
$VhdxPath = Join-Path $VmPath "$VmName.vhdx"

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "[Terraform] Creating VM '$VmName' from Golden Image..." -ForegroundColor Green

    if (-not (Test-Path $MasterVhdxPath)) {
        Write-Error "Master Golden VHDX not found at '$MasterVhdxPath'."
        exit 1
    }

    if (Test-Path $VmPath) {
        Remove-Item -Path $VmPath -Recurse -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $VmPath -Force | Out-Null

    Write-Host "[Terraform] Copying VHDX to $VhdxPath..." -ForegroundColor Cyan
    Copy-Item -Path $MasterVhdxPath -Destination $VhdxPath -Force
    Set-ItemProperty -Path $VhdxPath -Name IsReadOnly -Value $false

    New-VM -Name $VmName -MemoryStartupBytes ($RamMb * 1MB) -Generation 2 -VHDPath $VhdxPath -Path $VmsDir -SwitchName $SwitchName | Out-Null
    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes (2048MB) -MaximumBytes ($RamMb * 2 * 1MB) | Out-Null
    Set-VMProcessor -VMName $VmName -Count $Cpus | Out-Null
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On | Out-Null

    Write-Host "[Terraform] VM $VmName created. Starting VM..." -ForegroundColor Green
    Start-VM -Name $VmName | Out-Null
} else {
    Write-Host "[Terraform] VM $VmName already exists." -ForegroundColor Green
    if ($vm.State -ne 'Running') {
        Start-VM -Name $VmName | Out-Null
    }
}
