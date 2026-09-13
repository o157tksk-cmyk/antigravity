# ==============================================================================
# Windows Server 2022 Active Directory 構築スクリプト (PowerShell)
#
# 目的: Windows Server 2022 上で AD DS サービスを導入し「hogehoge.local」ドメインを作成
# 実行環境: Windows Server 2022 仮想マシン内で管理者権限で実行
# ==============================================================================

# 1. 管理者権限チェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは Windows Server 内で管理者として実行する必要があります。"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Active Directory (hogehoge.local) 構築開始" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# ネットワーク静的IP設定
$IPAddress    = "192.168.10.10"
$PrefixLength = 24
$Gateway      = "192.168.10.1"
$DNSAddress   = "127.0.0.1"
$DomainName   = "hogehoge.local"
$NetBiosName  = "HOGEHOGE"

# 2. 静的IPアドレスの設定
Write-Host "[1/3] 静的IPアドレス ($IPAddress) の設定中..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Status -eq "Up" | Select-Object -First 1

if ($adapter) {
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DNSAddress | Out-Null
    Write-Host "  -> ネットワーク設定が完了しました。" -ForegroundColor Green
} else {
    Write-Warning "アクティブなネットワークアダプターが見つかりませんでした。事前にネットワークを設定してください。"
}

# 3. Active Directory ドメイン サービス (AD DS) 機能のインストール
Write-Host "[2/3] AD DS ロールおよび管理ツールのインストール中..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
Write-Host "  -> AD DS 機能の導入が完了しました。" -ForegroundColor Green

# 4. フォレスト/ドメイン昇格処理 (hogehoge.local)
Write-Host "[3/3] ドメイン '$DomainName' の新規フォレスト構築とドメインコントローラー昇格を開始します..." -ForegroundColor Yellow
Write-Host "※設定完了後、サーバーは自動的に再起動します。" -ForegroundColor Red

# DSRM パスワード設定 (初期値: P@ssw0rd2022! 必要に応じて変更してください)
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
