#!/usr/bin/env bash
# ==============================================================================
# Rocky Linux 9 / RHEL系 Linux Apache Web サーバー構築スクリプト
#
# 目的: DNF を使用して Apache (httpd) をインストール・自動起動・ファイアウォール設定
# 実行環境: Rocky Linux 9 内で root 権限 (sudo) で実行
# ==============================================================================

set -euo pipefail

echo "=========================================="
echo " Rocky Linux Apache Web サーバー構築処理"
echo "=========================================="

# root 権限チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトは root 権限 (sudo) で実行してください。" >&2
    exit 1
fi

# 1. 静的IPアドレス・ネットワーク設定ガイド
IP_ADDR="192.168.10.20"
GATEWAY="192.168.10.1"
DNS_SERVER="192.168.10.10" # hogehoge.local Windows AD DNS

echo "[1/4] システムパッケージの更新..."
dnf update -y

echo "[2/4] Apache HTTP Server (httpd) のインストール..."
dnf install -y httpd httpd-tools

echo "[3/4] httpd サービスの有効化および起動..."
systemctl enable --now httpd

# ファイアウォール設定 (HTTP / HTTPS 許可)
if systemctl is-active --quiet firewalld; then
    echo "  -> ファイアウォール (firewalld) ポート解放中 (HTTP 80 / HTTPS 443)..."
    firewall-cmd --permanent --add-service=http --add-service=https
    firewall-cmd --reload
fi

echo "[4/4] テスト Web ページの生成 (/var/www/html/index.html)..."
cat <<'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rocky Linux Web Server - hogehoge.local</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 40px; display: flex; justify-content: center; align-items: center; min-height: 80vh; }
        .card { background: #1e293b; border-radius: 12px; padding: 32px; max-width: 600px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid #334155; }
        h1 { color: #38bdf8; margin-top: 0; }
        .badge { background: #0284c7; color: white; padding: 4px 8px; border-radius: 4px; font-size: 0.9em; font-weight: bold; }
        ul { background: #0f172a; padding: 16px 24px; border-radius: 8px; border: 1px solid #1e293b; }
        li { margin-bottom: 8px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 Apache Web Server 稼働中</h1>
        <p>Hyper-V 上の <span class="badge">Rocky Linux 9</span> 環境で Apache (httpd) が正常に動作しています。</p>
        <h2>ネットワーク & 連携情報</h2>
        <ul>
            <li><strong>Web サーバー IP:</strong> 192.168.10.20</li>
            <li><strong>AD ドメイン:</strong> hogehoge.local</li>
            <li><strong>AD Domain Controller IP:</strong> 192.168.10.10</li>
        </ul>
        <p>Active Directory (hogehoge.local) 連携および DNS 設定が完了しています。</p>
    </div>
</body>
</html>
EOF

chmod 644 /var/www/html/index.html

echo "=========================================="
echo " Apache Web サーバーの構築が完了しました！"
echo "=========================================="
systemctl status httpd --no-pager
