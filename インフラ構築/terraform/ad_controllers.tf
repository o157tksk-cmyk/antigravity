# ==============================================================================
# Active Directory Domain Controllers (ad_controllers.tf)
# 役割: Win2022-DC01 (Primary DC) & Win2022-DC02 (Replica DC) の作成と AD 昇格
# ==============================================================================

# 1. Primary Domain Controller (Win2022-DC01)
resource "null_resource" "ad_dc01" {
  depends_on = [null_resource.hyperv_switch]

  triggers = {
    vm_name      = var.dc01_vm_name
    ip_address   = var.dc01_ip
    domain_name  = var.domain_name
    netbios_name = var.domain_netbios
    vms_dir      = var.vms_dir
    switch_name  = var.switch_name
  }

  # VM 作成 & 起動
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\create_ad_vm.ps1 -VmName '${var.dc01_vm_name}' -VmsDir '${var.vms_dir}' -MasterVhdxPath '${var.win_master_vhdx_path}' -SwitchName '${var.switch_name}' -RamMb ${var.dc_ram_mb} -Cpus ${var.dc_cpus}"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # Primary AD フォレスト昇格プロビジョニング
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\provision_ad_dc01.ps1 -VmName '${var.dc01_vm_name}' -IpAddress '${var.dc01_ip}' -GatewayIp '${var.gateway_ip}' -PrefixLength ${var.prefix_length} -DomainName '${var.domain_name}' -NetbiosName '${var.domain_netbios}' -AdminPassword '${var.ad_admin_password}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # 削除時クリーンアップ
  provisioner "local-exec" {
    when        = destroy
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\destroy_vm.ps1 -VmName '${self.triggers.vm_name}' -VmsDir '${self.triggers.vms_dir}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }
}

# 2. Replica Domain Controller (Win2022-DC02)
resource "null_resource" "ad_dc02" {
  depends_on = [null_resource.ad_dc01]

  triggers = {
    vm_name      = var.dc02_vm_name
    ip_address   = var.dc02_ip
    domain_name  = var.domain_name
    netbios_name = var.domain_netbios
    vms_dir      = var.vms_dir
    switch_name  = var.switch_name
  }

  # VM 作成 & 起動
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\create_ad_vm.ps1 -VmName '${var.dc02_vm_name}' -VmsDir '${var.vms_dir}' -MasterVhdxPath '${var.win_master_vhdx_path}' -SwitchName '${var.switch_name}' -RamMb ${var.dc_ram_mb} -Cpus ${var.dc_cpus}"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # Replica AD 昇格 & ドメイン参加プロビジョニング
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\provision_ad_dc02.ps1 -VmName '${var.dc02_vm_name}' -IpAddress '${var.dc02_ip}' -PrimaryDcIp '${var.dc01_ip}' -GatewayIp '${var.gateway_ip}' -PrefixLength ${var.prefix_length} -DomainName '${var.domain_name}' -NetbiosName '${var.domain_netbios}' -AdminPassword '${var.ad_admin_password}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # 削除時クリーンアップ
  provisioner "local-exec" {
    when        = destroy
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\destroy_vm.ps1 -VmName '${self.triggers.vm_name}' -VmsDir '${self.triggers.vms_dir}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }
}
