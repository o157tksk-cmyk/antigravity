# ==============================================================================
# Active Directory Side Configuration Script (DNS Forwarder, Records, LDAP User)
# ==============================================================================

param (
    [string]$DomainName = "hogehoge.local",
    [string]$LinuxSrvIp = "192.168.10.20",
    [string]$LdapUser   = "svc_ldap",
    [string]$LdapPass   = "P@ssw0rd2022!",
    [string]$WebHost    = "web",
    [string]$MailHost   = "mail",
    [string]$DnsHost    = "ns"
)

Import-Module DnsServer -ErrorAction SilentlyContinue
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

Write-Host "Configuring Active Directory settings..." -ForegroundColor Green
Write-Host "Domain: $DomainName" -ForegroundColor Cyan
Write-Host "Linux IP: $LinuxSrvIp" -ForegroundColor Cyan

# 1. DNS Forwarder (Rocky Linux External DNS)
try {
    Set-DnsServerForwarder -IPAddress @($LinuxSrvIp) -UseRootHint $false -ErrorAction Stop
    Write-Host "[OK] DNS Forwarder configured: $LinuxSrvIp" -ForegroundColor Green
} catch {
    Write-Warning "DNS Forwarder warning: $_"
}

# 2. A Records
$records = @("srv01", $WebHost, $MailHost, $DnsHost)
foreach ($r in $records) {
    if ($r) {
        Remove-DnsServerResourceRecord -ZoneName $DomainName -Name $r -RRType A -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -ZoneName $DomainName -Name $r -IPv4Address $LinuxSrvIp -CreatePtr -ErrorAction SilentlyContinue
        Write-Host "[OK] A Record added: $r.$DomainName -> $LinuxSrvIp" -ForegroundColor Green
    }
}

# 3. MX Record
$mailFqdn = "$MailHost.$DomainName."
$existingMx = Get-DnsServerResourceRecord -ZoneName $DomainName -RRType MX -ErrorAction SilentlyContinue | Where-Object { $_.RecordData.MailExchange -like "*$MailHost*" }
if (-not $existingMx) {
    Add-DnsServerResourceRecordMX -ZoneName $DomainName -Name "@" -MailExchange $mailFqdn -Preference 10 -ErrorAction SilentlyContinue
    Write-Host "[OK] MX Record added: @ -> $mailFqdn (Priority 10)" -ForegroundColor Green
}

# 4. LDAP Service Account
$secPass = ConvertTo-SecureString $LdapPass -AsPlainText -Force
$existingUser = Get-ADUser -Filter "sAMAccountName -eq '$LdapUser'" -ErrorAction SilentlyContinue
if (-not $existingUser) {
    New-ADUser -Name $LdapUser -SamAccountName $LdapUser -UserPrincipalName "$LdapUser@$DomainName" -AccountPassword $secPass -Enabled $true -PasswordNeverExpires $true -Description "Service Account for Linux LDAP Auth"
    Write-Host "[OK] LDAP Service Account created: $LdapUser" -ForegroundColor Green
} else {
    Set-ADAccountPassword -Identity $LdapUser -NewPassword $secPass -Reset
    Set-ADUser -Identity $LdapUser -Enabled $true -PasswordNeverExpires $true
    Write-Host "[OK] LDAP Service Account updated: $LdapUser" -ForegroundColor Green
}

# 5. Test User
$testUser = "testuser01"
$existingTest = Get-ADUser -Filter "sAMAccountName -eq '$testUser'" -ErrorAction SilentlyContinue
if (-not $existingTest) {
    New-ADUser -Name $testUser -SamAccountName $testUser -UserPrincipalName "$testUser@$DomainName" -AccountPassword $secPass -Enabled $true -PasswordNeverExpires $true -Description "Test User for Web and Mail LDAP Auth"
    Write-Host "[OK] Test User created: $testUser" -ForegroundColor Green
}

Write-Host "Active Directory Configuration Completed Successfully!" -ForegroundColor Green
