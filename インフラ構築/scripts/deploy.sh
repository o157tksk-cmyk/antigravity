#!/usr/bin/env bash
# ==========================================
# インフラ・アプリケーションデプロイスクリプト
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== インフラ・アプリケーションデプロイ処理を開始します ==="

# 1. コンテナのビルドと起動
echo "[1/2] Docker Compose によるサービス構築中..."
cd "${INFRA_DIR}"
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d --build
    echo "  -> Docker Compose サービスが起動しました。"
else
    echo "  -> docker-compose が未インストールのためスキップされました。"
fi

# 2. 起動ステータスの確認
echo "[2/2] サービスステータスの確認中..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose ps
fi

echo "=== デプロイ処理が正常に完了しました ==="
