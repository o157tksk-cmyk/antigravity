#!/usr/bin/env bash
# ==========================================
# 初期環境自動セットアップ・検証スクリプト
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== インフラ初期環境セットアップを開始します ==="
echo "Working directory: ${INFRA_DIR}"

# 1. 依存ツールの確認
echo "[1/3] 依存ツールの確認中..."

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "  - $1: インストール済み ($( $1 --version 2>&1 | head -n 1 ))"
    else
        echo "  - $1: 未検出 (推奨ツール)"
    fi
}

check_cmd docker
check_cmd docker-compose
check_cmd terraform

# 2. .env ファイルの準備
echo "[2/3] 環境設定ファイル (.env) の確認中..."
if [ ! -f "${INFRA_DIR}/.env" ]; then
    if [ -f "${INFRA_DIR}/.env.example" ]; then
        cp "${INFRA_DIR}/.env.example" "${INFRA_DIR}/.env"
        echo "  -> .env.example から .env を作成しました。"
    else
        echo "  -> 警告: .env.example が見つかりません。"
    fi
else
    echo "  -> 既存の .env ファイルが存在します。"
fi

# 3. 終了メッセージ
echo "[3/3] セットアップチェックが完了しました。"
echo "=== 正常終了しました ==="
