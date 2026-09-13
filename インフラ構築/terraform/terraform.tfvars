# ==============================================================================
# Terraform Variables Values (terraform.tfvars)
# ==============================================================================

# Active Directory 設計パラメータ
domain_name          = "hogehoge.local"
domain_netbios       = "HOGEHOGE"
ad_admin_user        = "Administrator"
ad_admin_password    = "P@ssw0rd2022!"

# AD ドメインコントローラー VM 定義
dc01_vm_name         = "Win2022-DC01"
dc01_ip              = "192.168.10.10"
dc02_vm_name         = "Win2022-DC02"
dc02_ip              = "192.168.10.11"
dc_ram_mb            = 4096
dc_cpus              = 2
win_master_vhdx_path = "C:\\HyperV\\Master\\Win2022-GoldenImage.vhdx"

# Rocky Linux アプリケーションサーバー VM 定義
services_vm_name     = "Rocky9-AppSrv"
services_vm_ip       = "192.168.10.20"
services_vm_ram_mb   = 4096
services_vm_cpus     = 2
master_vhdx_path     = "C:\\HyperV\\Master\\Rocky9-Golden.vhdx"

# ネットワーク & 共通パス
switch_name          = "LabInternalSwitch"
gateway_ip           = "192.168.10.1"
prefix_length        = 24
vms_dir              = "C:\\HyperV\\VMs"

# LDAP サービス連携
ldap_user            = "svc_ldap"
ldap_pass            = "P@ssw0rd2022!"
