# Ansible による Windows Server AD & Rocky Linux 10 全自動構築ガイド

本フォルダ（`インフラ構築/ansible/`）には、Windows Server 2022（Active Directory ドメイン `hogehoge.local`）および Rocky Linux 10（Apache Web サーバー）を全自動構築するための Ansible Playbook および役割（Roles）が格納されています。

---

## 📁 構成ファイルマップ

```text
ansible/
├── ansible.cfg                    # Ansible 実行構成ファイル
├── inventory.ini                  # ターゲットホスト定義 (192.168.10.10 / 192.168.10.20)
├── playbook.yml                   # メイン Playbook
├── README_ANSIBLE.md              # 本ドキュメント
└── roles/                         # 役割定義ディレクトリ
    ├── windows_ad/                # Windows AD DS & hogehoge.local 昇格タスク
    │   └── tasks/main.yml
    └── linux_web/                 # Rocky Linux 10 Apache & firewalld タスク
        └── tasks/main.yml
```

---

## 🚀 クイックスタート (Ansible の実行手順)

### 1. 前提条件のインストール (WSL / Linux 上)
コントロールノード（WSL または Linux）に Ansible および必要なコレクションをインストールします。

```bash
# Ansible のインストール
pip install ansible pywinrm

# 必要な Ansible コレクションのインストール
ansible-galaxy collection install ansible.windows microsoft.ad ansible.posix
```

### 2. 構文チェック
```bash
cd インフラ構築/ansible
ansible-playbook --syntax-check playbook.yml
```

### 3. Playbook の実行 (全自動構築)
```bash
ansible-playbook -i inventory.ini playbook.yml
```

---

## 🎯 実行後の構築結果

1. **Windows Server 2022 (`192.168.10.10`)**
   - Active Directory フォレスト/ドメイン `hogehoge.local` 昇格完了
   - DNS サーバー有効化

2. **Rocky Linux 10 (`192.168.10.20`)**
   - Apache (`httpd`) インストール・稼働中
   - 80/443 ポート解放済み
   - アクセス確認ページ配置完了
