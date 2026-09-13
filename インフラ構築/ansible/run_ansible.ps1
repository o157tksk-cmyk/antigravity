# ==============================================================================
# PowerShell から Ansible Playbook を実行するラッパースクリプト
#
# 目的: WSL (Windows Subsystem for Linux) を経由して PowerShell からワンクリックで Ansible を実行
# 実行環境: Windows の PowerShell (WSL 有効環境)
# ==============================================================================

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Ansible 全自動構築の開始 (WSL 経由)" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

# 1. WSL のインストールチェック
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "エラー: WSL (Windows Subsystem for Linux) がインストールされていません。"
    Write-Host "PowerShell で 'wsl --install' を実行して WSL をインストールしてください。" -ForegroundColor Yellow
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 2. WSL 内で Ansible および依存パッケージの自動セットアップ & Playbook 実行
Write-Host "[1/2] WSL 内で Ansible 依存ライブラリの確認および Playbook 実行準備中..." -ForegroundColor Yellow

$wslCmd = @"
cd `$(wslpath '$ScriptDir')
if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "-> Ansible をインストール中..."
    sudo apt-get update -qq && sudo apt-get install -y -qq python3-pip python3-full >/dev/null 2>&1 || true
    pip3 install --quiet ansible pywinrm 2>/dev/null || pip install --quiet ansible pywinrm
    ansible-galaxy collection install ansible.windows microsoft.ad ansible.posix >/dev/null 2>&1 || true
fi

echo "-> ansible-playbook を実行中..."
ansible-playbook -i inventory.ini playbook.yml
"@

wsl bash -c "$wslCmd"

Write-Host "==========================================" -ForegroundColor Green
Write-Host " Ansible による全自動プロビジョニング完了" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
