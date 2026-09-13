# ==============================================================================
# DC01 初期設定 & Primary AD (hogehoge.local) 昇格自動化スクリプト
#
# 目的: Win2022-DC01 の静的 IP (192.168.10.10) 設定、AD DS 導入、hogehoge.local 昇格
# 実行環境: Win2022-DC01 内部で管理者権限で実行
# ==============================================================================

# 1. 管理者権限チェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは Windows Server 内で管理者として実行する必要があります。"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Win2022-DC01 ネットワーク設定 & AD 昇格" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# ネットワーク静的IP設定
$IPAddress    = "192.168.10.10"
$PrefixLength = 24
$Gateway      = "192.168.10.1"
$DNSAddress   = "127.0.0.1"
$DomainName   = "hogehoge.local"
$NetBiosName  = "HOGEHOGE"

# 2. ホスト名変更
if ($env:COMPUTERNAME -ne "Win2022-DC01") {
    Write-Host "[1/4] ホスト名を 'Win2022-DC01' に変更中..." -ForegroundColor Yellow
    Rename-Computer -NewName "Win2022-DC01" -Force | Out-Null
}

# 3. 静的IPアドレスの設定
Write-Host "[2/4] 静的IPアドレス ($IPAddress) の設定中..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1

if ($adapter) {
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DNSAddress | Out-Null
    Write-Host "  -> ネットワーク設定完了。" -ForegroundColor Green
}

# 4. AD DS ロールのインストール
Write-Host "[3/4] AD DS ロールおよび管理ツールのインストール中..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
Write-Host "  -> AD DS 機能の導入完了。" -ForegroundColor Green

# 5. フォレスト/ドメイン昇格処理 (hogehoge.local)
Write-Host "[4/4] ドメイン '$DomainName' の新規フォレスト構築とドメインコントローラー昇格を開始..." -ForegroundColor Yellow
Write-Host "※昇格完了後、サーバーは自動的に再起動します。" -ForegroundColor Red

$SecurePassword = ConvertTo-SecureString "P@ssw0rd2022!" -AsPlainText -Force

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetBiosName `
    -SafeModeAdministratorPassword $SecurePassword `
    -InstallDns:$true `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true
