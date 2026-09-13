# ==============================================================================
# Create Internal Virtual Switch
# ==============================================================================

param (
    [string]$SwitchName = "LabInternalSwitch",
    [string]$GatewayIp  = "192.168.10.1",
    [int]$PrefixLength  = 24
)

Write-Host "[Terraform] Checking Virtual Switch: $SwitchName..." -ForegroundColor Cyan

if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    Write-Host "[Terraform] Creating Internal VMSwitch: $SwitchName..." -ForegroundColor Green
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Start-Sleep -Seconds 2
    
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$SwitchName*" -or $_.Name -like "*$SwitchName*" }
    if ($adapter) {
        New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $GatewayIp -PrefixLength $PrefixLength -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[Terraform] Assigned IP $GatewayIp to $SwitchName adapter." -ForegroundColor Green
    }
} else {
    Write-Host "[Terraform] Virtual Switch $SwitchName already exists." -ForegroundColor Green
}

# Ensure NAT is configured for internal subnet
$subnetPrefix = "$GatewayIp/$PrefixLength".Replace(".1/24", ".0/24")
if (-not (Get-NetNat -Name "LabInternalNat" -ErrorAction SilentlyContinue)) {
    try {
        New-NetNat -Name "LabInternalNat" -InternalIPInterfaceAddressPrefix $subnetPrefix -ErrorAction Stop | Out-Null
        Write-Host "[Terraform] Created NAT rule for $subnetPrefix" -ForegroundColor Green
    } catch {
        Write-Warning "Could not create NetNat: $_"
    }
}

