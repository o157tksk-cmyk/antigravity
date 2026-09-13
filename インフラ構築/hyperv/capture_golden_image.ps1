# ==============================================================================
# ゴールデンイメージ キャプチャ & 保護スクリプト
# 
# 目的: Sysprep シャットダウン完了後の VHDX を GoldenImage.vhdx として保護保存
# 実行要件: 管理者権限で実行してください (Run as Administrator)
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージ キャプチャ処理" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$VmName        = "Win2022-Template"
$SourceVhdx    = "C:\HyperV\VMs\Win2022-Template\Win2022-Template.vhdx"
$GoldenVhdx    = "C:\HyperV\Master\Win2022-GoldenImage.vhdx"

# 1. VM ステータス確認
$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($vm) {
    if ($vm.State -ne "Off") {
        Write-Error "エラー: VM '$VmName' がまだシャットダウンしていません。現在の状態: $($vm.State)"
        Write-Host "VM が Sysprep を完了して自動シャットダウンするまでお待ちください。" -ForegroundColor Yellow
        exit 1
    }
} else {
    if (-not (Test-Path $SourceVhdx)) {
        Write-Error "エラー: 原本 VHDX '$SourceVhdx' が見つかりません。"
        exit 1
    }
}

# 2. キャプチャ＆保護処理
Write-Host "[1/2] VHDX を '$GoldenVhdx' へキャプチャ複製中..." -ForegroundColor Yellow
if (Test-Path $GoldenVhdx) {
    Set-ItemProperty -Path $GoldenVhdx -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Remove-Item $GoldenVhdx -Force
}

Copy-Item -Path $SourceVhdx -Destination $GoldenVhdx -Force

# 読み取り専用に設定して保護
Set-ItemProperty -Path $GoldenVhdx -Name IsReadOnly -Value $true
Write-Host "  -> Master VHDX を読み取り専用に設定し保護しました。" -ForegroundColor Green

# 3. クリーンアップ
Write-Host "[2/2] テンプレート VM のクリーンアップ..." -ForegroundColor Yellow
if ($vm) { Remove-VM -Name $VmName -Force | Out-Null }

Write-Host "==========================================" -ForegroundColor Green
Write-Host " ゴールデンイメージの作成が完了しました！" -ForegroundColor Green
Write-Host " 保存パス: $GoldenVhdx" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Green
