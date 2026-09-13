# ==============================================================================
# 全インフラ (Windows AD 2台 + Rocky Linux Web/DNS/Mail) 完全自動構築マスター
# 
# 概要:
#   Hyper-V ホスト上で本スクリプトを管理者として実行するだけで、
#   AD ドメイン (Win2022-DC01 / Win2022-DC02) の構築から、
#   Rocky Linux 9 (Web / 外部DNS / メール) のゴールデンイメージ作成・デプロイ・AD連携・テストまで
#   全てのインフラを完全無人で一気に構築します。
# 
# 実行要件: 管理者権限の PowerShell (Run as Administrator)
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "エラー: 本スクリプトは管理者権限で実行する必要があります。"
    exit 1
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=================================================================" -ForegroundColor Green
Write-Host " 全インフラ (Active Directory 2台 + Rocky Linux サービス) 完全自動構築" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host ""

# フェーズ 1: Active Directory 2台の全自動構築
Write-Host ">>> [PHASE 1] Active Directory (DC01 / DC02) の全自動構築を開始します..." -ForegroundColor Magenta
& "$ScriptDir\setup_all_ad.ps1"

# フェーズ 2: Rocky Linux 9 ゴールデンイメージ & サービス構築 & AD連携
Write-Host "`n>>> [PHASE 2] Rocky Linux 9 (Web / 外部DNS / Mail) & AD連携 自動構築を開始します..." -ForegroundColor Magenta
& "$ScriptDir\setup_all_rocky_services.ps1"

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " 🎉 全インフラの完全自動プロビジョニングが正常に完了しました！" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
