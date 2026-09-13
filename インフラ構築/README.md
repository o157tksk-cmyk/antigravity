# インフラ自動構築 & 構成管理

本ディレクトリ（`インフラ構築`）には、Hyper-V 仮想環境における **Windows Server 2022 Active Directory** および **Rocky Linux 9（Web / 外部DNS / メール）** のゴールデンイメージ作成、高速デプロイ、AD連携自動化スクリプト群が格納されています。

---

## 📁 ディレクトリ構成

```text
インフラ構築/
├── README.md                              # 本ドキュメント
├── HYPERV_SETUP_GUIDE.md                  # Hyper-V & AD・Rocky Linux 完全自動構築手順書
├── hyperv/                                # Hyper-V 仮想マシン作成 & AD連携自動化スクリプト
│   ├── config.json                        # 【マスター設定】全VM・ネットワーク・AD設定
│   ├── create_golden_template.ps1         # Windows Server 2022 ゴールデンイメージ作成
│   ├── create_rocky_golden_template.ps1   # Rocky Linux 9 ゴールデンイメージ作成 (Kickstart自動化)
│   ├── deploy_dcs_from_golden.ps1         # AD DC (Win2022-DC01) 高速デプロイ
│   ├── deploy_rocky_from_golden.ps1       # 実稼働Rocky9 (Rocky9-AppSrv) 高速デプロイ
│   ├── configure_ad_dc01.ps1              # AD DS フォレスト昇格スクリプト
│   └── configure_ad_dns_and_ldap.ps1      # AD側 外部DNSフォワーダー/レコード/LDAP設定
└── scripts/                               # Rocky Linux 側自動化スクリプト群
    ├── ks.cfg                             # Rocky Linux 9 Kickstart無人応答ファイル
    ├── services.env                       # Linux側環境変数定義 (config.json より自動生成)
    ├── setup_rocky_all_services.sh        # Rocky Linux内 DNS/Web/Mail一括自動セットアップ
    └── test_all_services.sh               # 統合検証テストスクリプト
```

---

## 🚀 クイックスタート

詳細な手順については **[HYPERV_SETUP_GUIDE.md](HYPERV_SETUP_GUIDE.md)** をご覧ください。

1. **設定の確認:** `hyperv/config.json` でIPやドメイン名を定義。
2. **Rocky Linux ゴールデンイメージ作成:**
   ```powershell
   .\hyperv\create_rocky_golden_template.ps1
   ```
   （`Rocky9-Template` が作成・一般化され、Hyper-V 管理コンソール上に「オフ」の状態で保持されます）
3. **実稼働VMデプロイ:**
   ```powershell
   .\hyperv\deploy_rocky_from_golden.ps1
   ```
4. **AD連携設定 (Windows Server 内部で実行):**
   ```powershell
   .\hyperv\configure_ad_dns_and_ldap.ps1
   ```
5. **Rocky Linux サービスセットアップ (Rocky Linux 内部で実行):**
   ```bash
   chmod +x ./scripts/setup_rocky_all_services.sh
   ./scripts/setup_rocky_all_services.sh
   ```
6. **総合テスト:**
   ```bash
   ./scripts/test_all_services.sh
   ```
