# Hyper-V 仮想環境 & Windows AD・Rocky Linux (Web/DNS/Mail) 完全自動化ガイド

本ガイドでは、Hyper-V 環境上に **Windows Server 2022**（Active Directory ドメイン `hogehoge.local`）と **Rocky Linux 9**（ゴールデンイメージからデプロイされた Web / 外部DNS / メールサーバー）を**ワンクリックで完全自動構築・連携**させる手順を解説します。

すべての設定は外部ファイル（`hyperv/config.json`）で一元管理されており、IPアドレスやドメイン名の変更、別環境への適用も容易に行えます。

---

## 🏗 システム構成 & ネットワークトポロジ

| 仮想マシン名 | OS | 役割 | IPアドレス / FQDN | 備考 |
|---|---|---|---|---|
| **`Win2022-DC01`** | Windows Server 2022 | AD DC, ドメインDNS, Kerberos/LDAP基盤 | `192.168.10.10`<br>`hogehoge.local` | 内部ゾーン管理 & 未解決クエリをLinuxへフォワード |
| **`Win2022-DC02`** | Windows Server 2022 | 冗長系 AD DC (オプション) | `192.168.10.11`<br>`hogehoge.local` | レプリケーションDC |
| **`Rocky9-Template`** | Rocky Linux 9 | **ゴールデンイメージ (マスターVM)** | DHCP / 一般化済み | **Hyper-V上で「オフ」状態で保持** |
| **`Rocky9-AppSrv`** | Rocky Linux 9 | **Web・外部DNS・メール統合サーバー** | `192.168.10.20`<br>`srv01.hogehoge.local` | ゴールデンイメージから即時複製デプロイ |
| **ホスト仮想スイッチ** | - | 内部スイッチ (`LabInternalSwitch`) | `192.168.10.1 / 24` | 内部通信用ゲートウェイ |

---

## ⚡ ワンクリック完全自動化（推奨実行方法）

### 📥 準備: ISOファイルの配置
以下のISOを `C:\HyperV\ISO\` に配置します（パスは `config.json` で変更可能）：
1. `C:\HyperV\ISO\WindowsServer2022.iso`
2. `C:\HyperV\ISO\RockyLinux9.iso`

---

### 🚀 パターンA: Rocky Linux サービス & AD連携のワンクリック構築 (前回ADがある場合)

管理者権限の PowerShell で以下のスクリプトを **1回実行するだけ** で完了します：

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process -Force
.\インフラ構築\hyperv\setup_all_rocky_services.ps1
```

> **全自動で実行される処理内容:**
> 1. `Rocky9-Template` VM の無人インストール・Sysprep相当の一般化・自動シャットダウン（**Hyper-V画面でオフ状態で保持**）
> 2. ゴールデンイメージから `Rocky9-AppSrv` (`192.168.10.20`) を複製・起動
> 3. Windows AD (`Win2022-DC01`) に対し、PowerShell Direct で **外部DNSフォワーダー（`192.168.10.20`）**、A/MXレコード、LDAP連携アカウント（`svc_ldap`）を自動登録
> 4. `Rocky9-AppSrv` に SSH 接続し、**BIND 9（外部DNS/キャッシュリゾルバ）**、**Apache（AD認証ポータル）**、**Postfix + Dovecot（AD認証メール）** を自動セットアップ
> 5. 総合検証テスト（DNS外部フォワード解決、Web認証、メール送受信）を自動実行し、結果を表示

---

### 🌐 パターンB: AD 2台 + Rocky Linux 全インフラの一括構築 (ゼロからの初期構築)

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process -Force
.\インフラ構築\hyperv\setup_all_infrastructure.ps1
```

---

## 📁 スクリプト一覧

```text
インフラ構築/
├── README.md                              # 全体概要ドキュメント
├── HYPERV_SETUP_GUIDE.md                  # 本構築ガイド
├── hyperv/
│   ├── config.json                        # 【マスター設定】全VM・ネットワーク・AD設定
│   ├── setup_all_rocky_services.ps1       # ★【ワンクリック】Rocky Linux & AD連携マスター
│   ├── setup_all_infrastructure.ps1       # ★【ワンクリック】AD 2台 + Rocky Linux 全インフラ構築
│   ├── setup_all_ad.ps1                   # AD 2台 (DC01/DC02) 自動構築マスター
│   ├── create_rocky_golden_template.ps1   # Rocky Linux 9 ゴールデンイメージ作成 (Kickstart自動化)
│   ├── deploy_rocky_from_golden.ps1       # 実稼働Rocky9 (Rocky9-AppSrv) 高速デプロイ
│   └── configure_ad_dns_and_ldap.ps1      # AD側 外部DNSフォワーダー/レコード/LDAP設定
└── scripts/
    ├── ks.cfg                             # Rocky Linux 9 Kickstart無人応答ファイル
    ├── services.env                       # Linux側環境変数 (deployスクリプトにより自動生成)
    ├── setup_rocky_all_services.sh        # Rocky Linux内 DNS/Web/Mail一括自動セットアップ
    └── test_all_services.sh               # 統合検証テストスクリプト
```
