# ==============================================================================
# ゴールデンイメージ汎用利用スクリプト: 任意の追加 Windows Server (例: ファイルサーバー) 高速自動構築
#
# 目的: C:\HyperV\Master\Win2022-GoldenImage.vhdx をマスターとして再利用し、
#       ファイルサーバー (Win2022-FS01) などの新 VM を数秒で作成・ドメイン参加まで自動化
# 実行例: .\deploy_vm_from_golden.ps1 -VmName "Win2022-FS01" -IPAddress "192.168.10.20" -JoinDomain:$true
# ==============================================================================

param (
    [string]$VmName = "Win2022-FS01",
    [string]$IPAddress = "192.168.10.20",
    [bool]$JoinDomain = $true
)

# 1. 管理者権限チェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$cfg = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

$MasterVhdx = Join-Path $cfg.paths.masterDir "Win2022-GoldenImage.vhdx"
$VmDir      = $cfg.paths.vmDir
$SwitchName = $cfg.network.switchName
$DomainName = $cfg.domain.name
$AdminUser  = "$($cfg.domain.netbios)\Administrator"
$AdminPass  = $cfg.admin.password

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージからの汎用 VM 高速展開: $VmName" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

if (-not (Test-Path $MasterVhdx)) {
    Write-Error "エラー: ゴールデンイメージ '$MasterVhdx' が存在しません。"
    exit 1
}

$VmPath   = Join-Path $VmDir $VmName
$VhdxPath = Join-Path $VmPath "$VmName.vhdx"

# 2. 既存 VM のクリーンアップ
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $VmName -TurnOff -ErrorAction SilentlyContinue | Out-Null
    Remove-VM -Name $VmName -Force | Out-Null
}
if (Test-Path $VmPath) { Remove-Item $VmPath -Recurse -Force | Out-Null }

New-Item -ItemType Directory -Path $VmPath -Force | Out-Null

# 3. マスター VHDX の高速コピー (ゴールデンイメージ本体は保護・不変)
Write-Host "[1/3] マスター VHDX からクローン作成中 (約10秒)..." -ForegroundColor Yellow
Copy-Item -Path $MasterVhdx -Destination $VhdxPath -Force
Set-ItemProperty -Path $VhdxPath -Name IsReadOnly -Value $false

# 4. Hyper-V VM の作成 & 起動
Write-Host "[2/3] 仮想マシン '$VmName' の作成および自動起動..." -ForegroundColor Yellow
New-VM -Name $VmName -MemoryStartupBytes 4GB -Generation 2 -VHDPath $VhdxPath -Path $VmDir -SwitchName $SwitchName | Out-Null
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB | Out-Null
Set-VMProcessor -VMName $VmName -Count 2 | Out-Null
Start-VM -Name $VmName | Out-Null

Write-Host "  -> VM 起動完了。OOBE スキップ処理を待機中 (40秒)..." -ForegroundColor Green
Start-Sleep -Seconds 40

# 5. ネットワーク & ホスト名 & ドメイン参加処理
Write-Host "[3/3] ホスト名 ($VmName), 静的 IP ($IPAddress), ドメイン参加 ($DomainName) の自動設定..." -ForegroundColor Yellow
$secPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force
$cred    = New-Object System.Management.Automation.PSCredential('Administrator', $secPass)

Invoke-Command -VMName $VmName -Credential $cred -ScriptBlock {
    param($Name, $IP, $GW, $Prefix, $DnsIP)
    Rename-Computer -NewName $Name -Force
    $ad = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    New-NetIPAddress -InterfaceIndex $ad.ifIndex -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $DnsIP
} -ArgumentList $VmName, $IPAddress, $cfg.network.gateway, $cfg.network.prefixLength, $cfg.dc01.ipAddress

# ホスト名適用のため再起動
Restart-VM -Name $VmName -Force
Start-Sleep -Seconds 15

if ($JoinDomain) {
    Write-Host "  -> ドメイン '$DomainName' への全自動参加中..." -ForegroundColor Green
    Invoke-Command -VMName $VmName -Credential $cred -ScriptBlock {
        param($Domain, $User, $Pass)
        $p = ConvertTo-SecureString $Pass -AsPlainText -Force
        $dCred = New-Object System.Management.Automation.PSCredential($User, $p)
        Add-Computer -DomainName $Domain -Credential $dCred -Restart -Force
    } -ArgumentList $DomainName, $AdminUser, $AdminPass
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " 仮想マシン '$VmName' ($IPAddress) の構築およびドメイン参加が完了しました！" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
