# ==============================================================================
# ゴールデンイメージからの 2 台の AD VM クローン高速展開スクリプト (config.json 対応)
#
# 目的: マスター VHDX (Win2022-GoldenImage.vhdx) から DC01 と DC02 を数秒で作成・Hyper-V 登録
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

# 1. 管理者権限のチェック
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.json"
$cfg = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージからの AD 2台 クローン高速展開" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$MasterVhdx = Join-Path $cfg.paths.masterDir "Win2022-GoldenImage.vhdx"
$VmDir      = $cfg.paths.vmDir
$SwitchName = $cfg.network.switchName

if (-not (Test-Path $MasterVhdx)) {
    Write-Error "エラー: ゴールデンイメージ '$MasterVhdx' が存在しません。build_golden_dism.ps1 を実行してください。"
    exit 1
}

# 仮想スイッチの確認
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    Write-Host "[1/4] 仮想スイッチ '$SwitchName' を作成中..." -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    $netAdapter = Get-NetAdapter -Name "*$SwitchName*" -ErrorAction SilentlyContinue
    if ($netAdapter) {
        New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $cfg.network.gateway -PrefixLength $cfg.network.prefixLength -ErrorAction SilentlyContinue | Out-Null
    }
}

# VM 作成用ヘルパー関数
function Deploy-DCVM {
    param (
        [string]$VmName
    )

    Write-Host "[展開中] $VmName..." -ForegroundColor Yellow
    $VmPath = Join-Path $VmDir $VmName
    $VhdxPath = Join-Path $VmPath "$VmName.vhdx"

    # 既存 VM の削除
    if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
        Stop-VM -Name $VmName -TurnOff -ErrorAction SilentlyContinue | Out-Null
        Remove-VM -Name $VmName -Force | Out-Null
    }
    if (Test-Path $VmPath) { Remove-Item $VmPath -Recurse -Force | Out-Null }

    New-Item -ItemType Directory -Path $VmPath -Force | Out-Null

    # ゴールデン VHDX の高速コピー
    Copy-Item -Path $MasterVhdx -Destination $VhdxPath -Force
    Set-ItemProperty -Path $VhdxPath -Name IsReadOnly -Value $false

    # VM 定義 (第2世代, 4GB RAM, 2 CPU)
    New-VM -Name $VmName -MemoryStartupBytes 4GB -Generation 2 -VHDPath $VhdxPath -Path $VmDir -SwitchName $SwitchName | Out-Null
    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB | Out-Null
    Set-VMProcessor -VMName $VmName -Count 2 | Out-Null

    Write-Host "  -> $VmName 登録完了。" -ForegroundColor Green
}

# 2. DC01 の展開
Write-Host "[2/4] Primary DC ($($cfg.dc01.vmName)) の展開中..." -ForegroundColor Yellow
Deploy-DCVM -VmName $cfg.dc01.vmName

# 3. DC02 の展開
Write-Host "[3/4] Replica DC ($($cfg.dc02.vmName)) の展開中..." -ForegroundColor Yellow
Deploy-DCVM -VmName $cfg.dc02.vmName

Write-Host "==========================================" -ForegroundColor Green
Write-Host " [4/4] 2 台の AD サーバー ($($cfg.dc01.vmName) / $($cfg.dc02.vmName)) のクローン展開完了！" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
