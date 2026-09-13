# ==============================================================================
# Provision Win2022-DC01 (Primary Active Directory Domain Controller)
# ==============================================================================

param (
    [string]$VmName = "Win2022-DC01",
    [string]$IpAddress = "192.168.10.10",
    [string]$GatewayIp = "192.168.10.1",
    [int]$PrefixLength = 24,
    [string]$DomainName = "hogehoge.local",
    [string]$NetbiosName = "HOGEHOGE",
    [string]$AdminPassword = "P@ssw0rd2022!"
)

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Provisioning Primary AD Domain Controller ($VmName)" -ForegroundColor Green
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
    Write-Host "`n[2/4] Setting Static IP ($IpAddress) & Installing AD-Domain-Services..." -ForegroundColor Yellow
    Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock {
        param($Name, $IP, $GW, $Prefix)
        Rename-Computer -NewName $Name -Force -ErrorAction SilentlyContinue
        $ad = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
        New-NetIPAddress -InterfaceIndex $ad.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses '127.0.0.1'
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    } -ArgumentList $VmName, $IpAddress, $GatewayIp, $PrefixLength

    Write-Host "`n[3/4] Promoting to Primary Forest Root ($DomainName)..." -ForegroundColor Yellow
    Invoke-Command -VMName $VmName -Credential $localCred -ScriptBlock {
        param($Domain, $NetBios, $Pass)
        $p = ConvertTo-SecureString $Pass -AsPlainText -Force
        Install-ADDSForest -DomainName $Domain -DomainNetbiosName $NetBios -SafeModeAdministratorPassword $p -InstallDns:$true -CreateDnsDelegation:$false -Force:$true
    } -ArgumentList $DomainName, $NetbiosName, $AdminPassword

    Restart-VM -Name $VmName -Force
    Start-Sleep -Seconds 10
} else {
    Write-Host "`n[2/4] AD-Domain-Services already installed." -ForegroundColor Green
}

# 3. ドメイン再起動後の接続確認
Write-Host "`n[4/4] Verifying Domain Controller Status..." -ForegroundColor Yellow
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
    param($IP, $Domain)
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object Status -eq 'Up').ifIndex -ServerAddresses $IP, '127.0.0.1'
    Restart-Service Netlogon, DNS -Force -ErrorAction SilentlyContinue
} -ArgumentList $IpAddress, $DomainName

Write-Host "[OK] Primary Domain Controller ($VmName) is Ready!" -ForegroundColor Green
