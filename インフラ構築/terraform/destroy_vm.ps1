# ==============================================================================
# Destroy Rocky Linux VM and VHDX
# ==============================================================================

param (
    [string]$VmName = "Rocky9-AppSrv",
    [string]$VmsDir = "C:\HyperV\VMs"
)

Write-Host "[Terraform] Destroying VM: $VmName..." -ForegroundColor Yellow

$vmDir = Join-Path $VmsDir $VmName

if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $VmName -Force
}

if (Test-Path $vmDir) {
    Remove-Item -Path $vmDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[Terraform] VM $VmName destroyed successfully." -ForegroundColor Green
