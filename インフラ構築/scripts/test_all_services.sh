#!/bin/bash
# ==============================================================================
# Rocky Linux 9 サービス統合検証スクリプト (DNS / Web / Mail)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/services.env"

if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
else
    DOMAIN_NAME="hogehoge.local"
    AD_DC_IP="192.168.10.10"
    SERVER_IP="192.168.10.20"
    ADMIN_USER="Administrator"
    ADMIN_PASS="P@ssw0rd2022!"
    LDAP_USER="svc_ldap"
    LDAP_PASS="P@ssw0rd2022!"
fi

echo "=========================================================="
echo " Rocky Linux 9 サービス統合検証テスト"
echo "=========================================================="
echo "ドメイン : $DOMAIN_NAME"
echo "AD IP    : $AD_DC_IP"
echo "自IP     : $SERVER_IP"
echo "=========================================================="
echo ""

PASSED=0
FAILED=0

check_result() {
    if [ "$1" -eq 0 ]; then
        echo -e "\e[32m[PASS]\e[0m $2"
        PASSED=$((PASSED + 1))
    else
        echo -e "\e[31m[FAIL]\e[0m $2"
        FAILED=$((FAILED + 1))
    fi
}

# ------------------------------------------------------------------------------
# 1. DNS サーバー検証 (外部フォワード & キャッシュ)
# ------------------------------------------------------------------------------
echo "--- 1. DNS サーバー検証 (BIND 9) ---"

# BIND 9 サービス状態
systemctl is-active --quiet named
check_result $? "BIND 9 (named) サービス稼働状態"

# 外部ドメインの名前解決 (Rocky Linux の DNS経由)
echo "外部ドメイン (google.com) をローカルDNS (127.0.0.1) 経由で解決中..."
if dig @127.0.0.1 google.com +short +time=3 | grep -E '^[0-9.]+$' > /dev/null; then
    check_result 0 "外部DNSフォワーダー名前解決 (google.com -> $(dig @127.0.0.1 google.com +short | head -n 1))"
else
    check_result 1 "外部DNSフォワーダー名前解決 (上位DNSへの転送失敗またはオフライン)"
fi

# AD DNS経由での内部名前解決
if dig @"$AD_DC_IP" "web.${DOMAIN_NAME}" +short +time=3 | grep -q "$SERVER_IP"; then
    check_result 0 "AD DNSによる内部名前解決 (web.${DOMAIN_NAME} -> $SERVER_IP)"
else
    check_result 1 "AD DNSによる内部名前解決 (AD側DNSレコード未登録または到達不可)"
fi

echo ""

# ------------------------------------------------------------------------------
# 2. Web サーバー検証 (Apache & AD LDAP認証)
# ------------------------------------------------------------------------------
echo "--- 2. Web サーバー検証 (Apache & AD LDAP) ---"

systemctl is-active --quiet httpd
check_result $? "Apache (httpd) サービス稼働状態"

# トップページアクセス
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/")
if [ "$HTTP_CODE" -eq 200 ]; then
    check_result 0 "ポータル公開ページ (HTTP 200 OK)"
else
    check_result 1 "ポータル公開ページアクセス失敗 (HTTP $HTTP_CODE)"
fi

# 保護ディレクトリへの非認証アクセス (401になるべき)
HTTP_UNAUTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/secure/")
if [ "$HTTP_UNAUTH" -eq 401 ]; then
    check_result 0 "AD保護ディレクトリ 非認証時アクセス拒否 (HTTP 401 Unauthorized)"
else
    check_result 1 "AD保護ディレクトリ 非認証挙動異常 (HTTP $HTTP_UNAUTH)"
fi

# 保護ディレクトリへのAD LDAP認証アクセス
HTTP_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" "http://localhost/secure/")
if [ "$HTTP_AUTH" -eq 200 ]; then
    check_result 0 "AD LDAP認証アクセス成功 (管理者: ${ADMIN_USER} -> HTTP 200 OK)"
else
    check_result 1 "AD LDAP認証アクセス失敗 (HTTP $HTTP_AUTH - AD接続・資格情報を確認)"
fi

echo ""

# ------------------------------------------------------------------------------
# 3. メールサーバー検証 (Postfix & Dovecot)
# ------------------------------------------------------------------------------
echo "--- 3. メールサーバー検証 (Postfix / Dovecot) ---"

systemctl is-active --quiet postfix
check_result $? "Postfix (SMTP) サービス稼働状態"

systemctl is-active --quiet dovecot
check_result $? "Dovecot (IMAP) サービス稼働状態"

# ポート疎通確認
if nc -z 127.0.0.1 25 2>/dev/null || (echo > /dev/tcp/127.0.0.1/25) 2>/dev/null; then
    check_result 0 "SMTP ポート (25) リッスン確認"
else
    check_result 1 "SMTP ポート (25) 接続不可"
fi

if nc -z 127.0.0.1 143 2>/dev/null || (echo > /dev/tcp/127.0.0.1/143) 2>/dev/null; then
    check_result 0 "IMAP ポート (143) リッスン確認"
else
    check_result 1 "IMAP ポート (143) 接続不可"
fi

# Dovecot LDAP 認証テスト
if doveadm auth test "${ADMIN_USER}" "${ADMIN_PASS}" >/dev/null 2>&1; then
    check_result 0 "Dovecot LDAP 認証テスト (${ADMIN_USER} ログイン成功)"
else
    check_result 1 "Dovecot LDAP 認証テスト (${ADMIN_USER} ログイン失敗 - AD LDAP確認)"
fi

# テストメール送信
echo "テストメール送信テスト中 (root -> root@localhost)..."
if echo "This is an automated test mail on ${SERVER_HOSTNAME}." | mail -s "Test Mail from Automation" root 2>/dev/null; then
    check_result 0 "Postfix ローカルメール送信コマンド実行"
else
    check_result 1 "Postfix メール送信失敗"
fi

echo ""
echo "=========================================================="
echo " 総合検証結果: PASS: ${PASSED} 件 / FAIL: ${FAILED} 件"
echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo -e "\e[32mすべてのテストが正常に完了しました！\e[0m"
    exit 0
else
    echo -e "\e[31m一部のテストに失敗しました。各設定やAD通信を確認してください。\e[0m"
    exit 1
fi
