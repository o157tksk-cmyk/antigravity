# ==============================================================================
# Provision Win2022-DC02 (Replica Active Directory Domain Controller)
# ==============================================================================

param (
    [string]$VmName = "Win2022-DC02",
    [string]$IpAddress = "192.168.10.11",
    [string]$PrimaryDcIp = "192.168.10.10",
    [string]$GatewayIp = "192.168.10.1",
    [int]$PrefixLength = 24,
    [string]$DomainName = "hogehoge.local",
    [string]$NetbiosName = "HOGEHOGE",
    [string]$AdminPassword = "P@ssw0rd2022!"
)

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Provisioning Replica AD Domain Controller ($VmName)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

$secPass = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$localCred = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)
$domainAdmin = "$NetbiosName\Administrator"
$domainCred = New-Object System.Management.Automation.PSCredential($domainAdmin, $secPass)

# 1. 起動ポーリング
Write-Host "[1/4] Waiting for $VmName PowerShell Direct..." -ForegroundColor Yellow
$Timeout = 180
$Elapsed = 0
$ready = $false
while ($Elapsed -lt $Timeout) {
    $t = Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock { $true } -ErrorAction SilentlyContinue
    if (-not $t) {
        $t = Invoke-Command -VMName $VmName -Credential $domainCred -ScriptBlock { $true } -ErrorAction SilentlyContinue
    }
    if ($t -eq $true) {
        $ready = $true
        Write-Host " [Connected in $Elapsed s]" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $Elapsed += 5
    Write-Host "." -NoNewline
}

# 2. ADDS 役割確認
$isAdInstalled = Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock {
    (Get-WindowsFeature -Name AD-Domain-Services).Installed
} -ErrorAction SilentlyContinue

if (-not $isAdInstalled) {
    Write-Host "`n[2/4] Setting Static IP ($IpAddress) & DNS Pointing to Primary DC ($PrimaryDcIp)..." -ForegroundColor Yellow
    Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock {
        param($Name, $IP, $GW, $Prefix, $DnsIP)
        Rename-Computer -NewName $Name -Force -ErrorAction SilentlyContinue
        $ad = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        New-NetIPAddress -InterfaceIndex $ad.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $DnsIP
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    } -ArgumentList $VmName, $IpAddress, $GatewayIp, $PrefixLength, $PrimaryDcIp

    Write-Host "`n[3/4] Promoting to Replica Domain Controller in $DomainName..." -ForegroundColor Yellow
    Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock {
        param($Domain, $Admin, $Pass)
        $p = ConvertTo-SecureString $Pass -AsPlainText -Force
        $dCred = New-Object System.Management.Automation.PSCredential($Admin, $p)
        Install-ADDSDomainController -DomainName $Domain -Credential $dCred -SafeModeAdministratorPassword $p -InstallDns:$true -CreateDnsDelegation:$false -Force:$true
    } -ArgumentList $DomainName, $domainAdmin, $AdminPassword

    Restart-VM -Name $VmName -Force
    Start-Sleep -Seconds 10
} else {
    Write-Host "`n[2/4] AD-Domain-Services already installed." -ForegroundColor Green
}

# 3. 再起動後の確認
Write-Host "`n[4/4] Verifying Replica Domain Controller Status..." -ForegroundColor Yellow
$ready = $false
$Elapsed = 0
while ($Elapsed -lt $Timeout) {
    $t = Invoke-Command -VMName $VmName -Credential $domainCred -ScriptBlock { $true } -ErrorAction SilentlyContinue
    if ($t -eq $true) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 5
    $Elapsed += 5
}

Invoke-Command -VMName $VmName -Credential $domainCred -ScriptBlock {
    param($PrimaryIP, $MyIP)
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object Status -eq 'Up').ifIndex -ServerAddresses $PrimaryIP, $MyIP
    Set-Service ADWS -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service ADWS -ErrorAction SilentlyContinue
    Restart-Service Netlogon, DNS -Force -ErrorAction SilentlyContinue
} -ArgumentList $PrimaryDcIp, $IpAddress

Write-Host "[OK] Replica Domain Controller ($VmName) is Ready!" -ForegroundColor Green
