# ==============================================================================
# 他環境 PC 用: Active Directory 2台 ワンクリック完全自動構築マスターメインスクリプト
#
# 特長:
# - 同一ディレクトリの config.json を参照
# - VM の起動・再起動完了をバックグラウンドでポーリング自動検知 (Wait-ForPowerShellDirect)
# - ゴールデンイメージを Hyper-V 上に「Win2022-GoldenImage」(オフ) として自動登録・保管
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "エラー: 設定ファイル '$ConfigFile' が存在しません。"
    exit 1
}

$cfg = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$DomainName  = $cfg.domain.name
$NetBiosName = $cfg.domain.netbios
$AdminPass   = $cfg.admin.password
$Dc01Name    = $cfg.dc01.vmName
$Dc01IP      = $cfg.dc01.ipAddress
$Dc02Name    = $cfg.dc02.vmName
$Dc02IP      = $cfg.dc02.ipAddress
$GatewayIP   = $cfg.network.gateway
$PrefixLen   = $cfg.network.prefixLength

# VMの起動・再起動完了をバックグラウンドで自動検知するポーリング関数
function Wait-ForPowerShellDirect {
    param (
        [string]$VMName,
        [PSCredential]$Credential,
        [int]$TimeoutSeconds = 120
    )
    Write-Host "  -> VM '$VMName' の起動完了をバックグラウンドで確認中..." -NoNewline
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $test = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock { $true } -ErrorAction SilentlyContinue
        if ($test -eq $true) {
            Write-Host " [完了! ($elapsed 秒)]" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host "." -NoNewline
    }
    Write-Host " [タイムアウト]" -ForegroundColor Red
    return $false
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Hyper-V AD 2台 ($DomainName) ワンクリック完全自動構築" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# 1. ゴールデンイメージ作成 (Hyper-V 上に Win2022-GoldenImage (オフ) として登録)
Write-Host "`n[STEP 1/5] DISM ゴールデンイメージの作成 & Hyper-V 登録 (オフ)..." -ForegroundColor Yellow
& "$ScriptDir\build_golden_dism.ps1"

# 2. DC01 & DC02 VM のクローン展開
Write-Host "`n[STEP 2/5] $Dc01Name & $Dc02Name VM のクローン作成・自動起動..." -ForegroundColor Yellow
& "$ScriptDir\deploy_dcs_from_golden.ps1"
Start-VM -Name $Dc01Name, $Dc02Name -ErrorAction SilentlyContinue | Out-Null

$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$localCred = New-Object System.Management.Automation.PSCredential('Administrator', $secPass)

# 初回 OOBE スキップ起動の確認
Write-Host "`n[STEP 3/5] VM の初回起動をバックグラウンド検知中..." -ForegroundColor Yellow
Wait-ForPowerShellDirect -VMName $Dc01Name -Credential $localCred
Wait-ForPowerShellDirect -VMName $Dc02Name -Credential $localCred

# 3. 初期 IP/ホスト名設定 & ADDS機能インストール
Write-Host "`n[STEP 4/5] 各 VM の初期設定 & $Dc01Name の Primary AD 昇格..." -ForegroundColor Yellow

# DC01 初期設定
Invoke-Command -VMName $Dc01Name -Credential $localCred -ScriptBlock {
    param($Name, $IP, $GW, $Prefix)
    Rename-Computer -NewName $Name -Force
    $ad = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    New-NetIPAddress -InterfaceIndex $ad.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses '127.0.0.1'
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
} -ArgumentList $Dc01Name, $Dc01IP, $GatewayIP, $PrefixLen

# DC02 初期設定
Invoke-Command -VMName $Dc02Name -Credential $localCred -ScriptBlock {
    param($Name, $IP, $GW, $Prefix, $DnsIP)
    Rename-Computer -NewName $Name -Force
    $ad = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    New-NetIPAddress -InterfaceIndex $ad.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $DnsIP
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
} -ArgumentList $Dc02Name, $Dc02IP, $GatewayIP, $PrefixLen, $Dc01IP

# ホスト名反映用再起動
Restart-VM -Name $Dc01Name, $Dc02Name -Force
Wait-ForPowerShellDirect -VMName $Dc01Name -Credential $localCred
Wait-ForPowerShellDirect -VMName $Dc02Name -Credential $localCred

# DC01 フォレスト昇格
Invoke-Command -VMName $Dc01Name -Credential $localCred -ScriptBlock {
    param($Domain, $NetBios, $Pass)
    $p = ConvertTo-SecureString $Pass -AsPlainText -Force
    Install-ADDSForest -DomainName $Domain -DomainNetbiosName $NetBios -SafeModeAdministratorPassword $p -InstallDns:$true -CreateDnsDelegation:$false -Force:$true
} -ArgumentList $DomainName, $NetBiosName, $AdminPass

Restart-VM -Name $Dc01Name -Force
$domainAdmin = "$NetBiosName\Administrator"
$domainCred = New-Object System.Management.Automation.PSCredential($domainAdmin, $secPass)
Wait-ForPowerShellDirect -VMName $Dc01Name -Credential $domainCred

# DC01 ネットワーク & ファイアウォール調整
Invoke-Command -VMName $Dc01Name -Credential $domainCred -ScriptBlock {
    param($IP, $Domain)
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object Status -eq 'Up').ifIndex -ServerAddresses $IP, '127.0.0.1'
    Add-DnsServerPrimaryZone -Name $Domain -ReplicationScope 'Forest' -ErrorAction SilentlyContinue
    Add-DnsServerResourceRecordA -ZoneName $Domain -Name '@' -IPv4Address $IP -ErrorAction SilentlyContinue
    Restart-Service Netlogon, DNS -Force
    nltest /dsregdns | Out-Null
} -ArgumentList $Dc01IP, $DomainName

# DC02 レプリカ DC 昇格
Write-Host "`n[STEP 5/5] Replica AD ($Dc02Name) の昇格 & ドメイン参加..." -ForegroundColor Yellow
Invoke-Command -VMName $Dc02Name -Credential $localCred -ScriptBlock {
    param($Domain, $Admin, $Pass)
    $p = ConvertTo-SecureString $Pass -AsPlainText -Force
    $dCred = New-Object System.Management.Automation.PSCredential($Admin, $p)
    Install-ADDSDomainController -DomainName $Domain -Credential $dCred -SafeModeAdministratorPassword $p -InstallDns:$true -CreateDnsDelegation:$false -Force:$true
} -ArgumentList $DomainName, $domainAdmin, $AdminPass

Restart-VM -Name $Dc02Name -Force
Wait-ForPowerShellDirect -VMName $Dc02Name -Credential $domainCred

Invoke-Command -VMName $Dc02Name -Credential $domainCred -ScriptBlock {
    param($Dc01IP, $Dc02IP)
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter | Where-Object Status -eq 'Up').ifIndex -ServerAddresses $Dc01IP, $Dc02IP
    Set-Service ADWS -StartupType Automatic
    Start-Service ADWS
    Restart-Service Netlogon, DNS -Force
} -ArgumentList $Dc01IP, $Dc02IP

Write-Host "==========================================" -ForegroundColor Green
Write-Host " 全構築が完了しました！最終検証結果:" -ForegroundColor Green
Invoke-Command -VMName $Dc01Name -Credential $domainCred -ScriptBlock {
    Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, Enabled
    repadmin /replsummary
}
Write-Host "==========================================" -ForegroundColor Green
