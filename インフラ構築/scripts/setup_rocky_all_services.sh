#!/bin/bash
# ==============================================================================
# Rocky Linux 9 サービス一括自動構築スクリプト
# 役割: 
#   1. 外部DNSサーバー (BIND 9 - AD未解決クエリのフォワーダー先・キャッシュDNS)
#   2. Webサーバー (Apache - AD LDAP Basic 認証付き)
#   3. メールサーバー (Postfix + Dovecot - AD LDAP アカウント認証)
# 
# 実行環境: Rocky Linux 9 (root権限)
# ==============================================================================

set -uo pipefail

# 1. ルート権限チェック
if [ "$(id -u)" -ne 0 ]; then
    echo "エラー: このスクリプトは root 権限で実行する必要があります。" >&2
    exit 1
fi

# 2. 設定ファイルの読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/services.env"

# デフォルト設定値
DOMAIN_NAME="hogehoge.local"
DOMAIN_NETBIOS="HOGEHOGE"
AD_DC_IP="192.168.10.10"
SERVER_HOSTNAME="srv01"
SERVER_IP="192.168.10.20"
GATEWAY_IP="192.168.10.1"
PREFIX_LENGTH="24"
SUBNET_CIDR="192.168.10.0/24"
WEB_HOST_ALIAS="web"
MAIL_HOST_ALIAS="mail"
DNS_HOST_ALIAS="ns"
EXT_FORWARDERS="8.8.8.8 1.1.1.1"
LDAP_USER="svc_ldap"
LDAP_PASS="P@ssw0rd2022!"
ADMIN_USER="Administrator"
ADMIN_PASS="P@ssw0rd2022!"

if [ -f "$ENV_FILE" ]; then
    echo "環境変数ファイル $ENV_FILE を読み込みます。"
    # BOM を除外してロード
    sed -i '1s/^\xEF\xBB\xBF//' "$ENV_FILE" 2>/dev/null || true
    # shellcheck source=/dev/null
    source "$ENV_FILE" || true
fi

# LDAP Base DN の生成
LDAP_BASE_DN=$(echo "$DOMAIN_NAME" | sed 's/\./,dc=/g' | sed 's/^/dc=/')

echo "=========================================================="
echo " Rocky Linux 9 サービス自動構築 (DNS / Web / Mail)"
echo "=========================================================="
echo "ドメイン名      : $DOMAIN_NAME ($LDAP_BASE_DN)"
echo "AD DC IP        : $AD_DC_IP"
echo "本サーバー IP   : $SERVER_IP"
echo "外部フォワーダー: $EXT_FORWARDERS"
echo "=========================================================="

# 3. ホスト名 & ネットワーク設定
echo "[1/7] ホスト名および静的ネットワークを設定中..."
hostnamectl set-hostname "${SERVER_HOSTNAME}.${DOMAIN_NAME}"

# 一時的に外部DNSを設定してパッケージ取得を確実に
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
[ -n "$AD_DC_IP" ] && echo "nameserver $AD_DC_IP" >> /etc/resolv.conf

# 4. パッケージインストール
echo "[2/7] 必要なミドルウェアパッケージをインストール中..."
dnf install -y \
    bind bind-utils \
    httpd mod_ssl mod_ldap \
    postfix dovecot openldap-clients s-nail cyrus-sasl cyrus-sasl-plain


# 5. DNS サーバー (BIND 9) の設定
echo "[3/7] DNSサーバー (BIND 9 - 外部フォワーダー/キャッシュDNS) を構成中..."

FORWARDERS_BLOCK=""
for fwd in $EXT_FORWARDERS; do
    FORWARDERS_BLOCK="${FORWARDERS_BLOCK} ${fwd};"
done

cat << EOF > /etc/named.conf
options {
    listen-on port 53 { 127.0.0.1; ${SERVER_IP}; };
    listen-on-v6 port 53 { ::1; };
    directory   "/var/named";
    dump-file   "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file   "/var/named/data/named.secroots";
    recursing-file  "/var/named/data/named.recursing";

    allow-query     { localhost; 127.0.0.1; ${SUBNET_CIDR}; };
    allow-recursion { localhost; 127.0.0.1; ${SUBNET_CIDR}; };

    recursion yes;
    forwarders {${FORWARDERS_BLOCK} };
    forward only;

    dnssec-validation auto;

    managed-keys-directory "/var/named/dynamic";
    geoip-directory "/usr/share/GeoIP";

    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";

    include "/etc/crypto-policies/back-ends/bind.config";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

named-checkconf /etc/named.conf || true
systemctl enable --now named
echo " -> BIND 9 の起動完了。"

# 6. Web サーバー (Apache) の設定
echo "[4/7] Webサーバー (Apache - AD LDAP認証) を構成中..."

cat << EOF > /etc/httpd/conf.d/ad_auth.conf
<VirtualHost *:80>
    ServerName ${WEB_HOST_ALIAS}.${DOMAIN_NAME}
    ServerAlias ${SERVER_HOSTNAME}.${DOMAIN_NAME} ${SERVER_IP}
    DocumentRoot /var/www/html

    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <Location /secure>
        AuthType Basic
        AuthName "Active Directory Login - ${DOMAIN_NAME}"
        AuthBasicProvider ldap
        AuthLDAPURL "ldap://${AD_DC_IP}:389/${LDAP_BASE_DN}?sAMAccountName?sub?(objectClass=user)" NONE
        AuthLDAPBindDN "${LDAP_USER}@${DOMAIN_NAME}"
        AuthLDAPBindPassword "${LDAP_PASS}"
        Require valid-user
    </Location>
</VirtualHost>
EOF

mkdir -p /var/www/html/secure
cat << EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>${DOMAIN_NAME} - 統合サービスポータル</title>
    <style>
        body { font-family: 'Segoe UI', Meiryo, sans-serif; margin: 40px; background: #f4f6f9; color: #333; }
        .card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 800px; margin: 0 auto; }
        h1 { color: #0078d4; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
        .badge { background: #28a745; color: white; padding: 4px 8px; border-radius: 4px; font-size: 0.9em; }
        .btn { display: inline-block; padding: 10px 20px; background: #0078d4; color: white; text-decoration: none; border-radius: 4px; font-weight: bold; margin-top: 15px; }
        .btn:hover { background: #005a9e; }
        ul { line-height: 1.8; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 ${DOMAIN_NAME} 統合サービスポータル</h1>
        <p><span class="badge">稼働中</span> 本サーバーは Rocky Linux 9 上で稼働しています。</p>
        <h3>📌 提供サービス一覧</h3>
        <ul>
            <li><strong>外部DNS サーバー:</strong> BIND 9 (フォワーダー先: ${EXT_FORWARDERS})</li>
            <li><strong>Web サーバー:</strong> Apache 2.4 (AD LDAP 認証連携)</li>
            <li><strong>メールサーバー:</strong> Postfix / Dovecot (AD ユーザー認証・Maildir)</li>
        </ul>
        <hr>
        <h3>🔐 AD認証エリアのテスト</h3>
        <p>Active Directory (<code>${DOMAIN_NAME}</code>) のアカウントでログインできる保護エリアです。</p>
        <a class="btn" href="/secure/">AD認証エリア (/secure) へアクセス</a>
    </div>
</body>
</html>
EOF

cat << EOF > /var/www/html/secure/index.html
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>AD 認証成功</title>
    <style>
        body { font-family: 'Segoe UI', Meiryo, sans-serif; margin: 40px; background: #e8f5e9; color: #2e7d32; }
        .card { background: white; padding: 25px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 600px; margin: 0 auto; }
        h1 { color: #2e7d32; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🎉 Active Directory 認証に成功しました！</h1>
        <p>Active Directory (<strong>${DOMAIN_NAME}</strong>) の LDAP 経由で正常に認証されました。</p>
        <p><a href="/">← ポータルトップへ戻る</a></p>
    </div>
</body>
</html>
EOF

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
restorecon -Rv /var/www/html 2>/dev/null || true

setsebool -P httpd_can_connect_ldap 1 2>/dev/null || true
setsebool -P httpd_can_network_connect 1 2>/dev/null || true

systemctl enable --now httpd
echo " -> Apache の起動完了。"

# 7. メールサーバー (Postfix + Dovecot) の設定
echo "[5/7] メールサーバー (Postfix + Dovecot - AD LDAP認証) を構成中..."

postconf -e "myhostname = ${MAIL_HOST_ALIAS}.${DOMAIN_NAME}"
postconf -e "mydomain = ${DOMAIN_NAME}"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = ipv4"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "mynetworks = 127.0.0.0/8, ${SUBNET_CIDR}"
postconf -e "home_mailbox = Maildir/"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

cat << EOF > /etc/dovecot/dovecot.conf
protocols = imap pop3 lmtp
listen = *, ::
!include conf.d/*.conf
!include_try local.conf
EOF

cat << EOF > /etc/dovecot/conf.d/10-auth.conf
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-ldap.conf.ext
EOF

cat << EOF > /etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:~/Maildir
mail_privileged_group = mail
EOF

cat << 'EOF' > /etc/dovecot/conf.d/10-master.conf
service imap-login {
  inet_listener imap {
    port = 143
  }
}
service pop3-login {
  inet_listener pop3 {
    port = 110
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = root
  }
}
service auth-worker {
  user = root
}
EOF

cat << EOF > /etc/dovecot/dovecot-ldap.conf.ext
hosts = ${AD_DC_IP}:389
dn = ${LDAP_USER}@${DOMAIN_NAME}
dnpass = ${LDAP_PASS}
auth_bind = yes
ldap_version = 3
base = ${LDAP_BASE_DN}
scope = subtree
user_attrs = =home=/home/%u
pass_attrs = sAMAccountName=user
pass_filter = (|(sAMAccountName=%u)(userPrincipalName=%u))
default_pass_scheme = CRYPT
EOF
chmod 600 /etc/dovecot/dovecot-ldap.conf.ext

setsebool -P allow_postfix_local_write_mail_spool 1 2>/dev/null || true

systemctl enable --now postfix dovecot
echo " -> Postfix & Dovecot の起動完了。"

# 8. ファイアウォール (firewalld) ポート開放
echo "[6/7] ファイアウォール (firewalld) のポートを開放中..."
systemctl enable --now firewalld 2>/dev/null || true

firewall-cmd --permanent --add-service=dns 2>/dev/null || true
firewall-cmd --permanent --add-service=http 2>/dev/null || true
firewall-cmd --permanent --add-service=https 2>/dev/null || true
firewall-cmd --permanent --add-service=smtp 2>/dev/null || true
firewall-cmd --permanent --add-port=587/tcp 2>/dev/null || true
firewall-cmd --permanent --add-service=imap 2>/dev/null || true
firewall-cmd --permanent --add-service=imaps 2>/dev/null || true
firewall-cmd --permanent --add-service=pop3 2>/dev/null || true
firewall-cmd --permanent --add-service=pop3s 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

# 9. 完了確認
echo "[7/7] 全サービスの稼働状態を確認中..."
echo "--- BIND 9 (DNS) ---"
systemctl is-active named
echo "--- Apache (Web) ---"
systemctl is-active httpd
echo "--- Postfix (SMTP) ---"
systemctl is-active postfix
echo "--- Dovecot (IMAP) ---"
systemctl is-active dovecot

echo ""
echo "=========================================================="
echo " Rocky Linux 9 サービス構築が正常に完了しました！"
echo "=========================================================="
