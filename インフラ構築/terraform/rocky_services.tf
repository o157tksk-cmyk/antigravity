# ==============================================================================
# Rocky Linux Services Virtual Machine (rocky_services.tf)
# ==============================================================================

resource "null_resource" "rocky_services_vm" {
  depends_on = [null_resource.hyperv_switch, null_resource.ad_dc01, null_resource.ad_dc02]

  triggers = {
    vm_name          = var.services_vm_name
    vm_ip            = var.services_vm_ip
    ram_mb           = var.services_vm_ram_mb
    cpus             = var.services_vm_cpus
    master_vhdx_path = var.master_vhdx_path
    vms_dir          = var.vms_dir
    switch_name      = var.switch_name
  }

  # 1. 仮想マシン作成 & 起動 (Apply時)
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\create_vm.ps1 -VmName '${var.services_vm_name}' -VmsDir '${var.vms_dir}' -MasterVhdxPath '${var.master_vhdx_path}' -SwitchName '${var.switch_name}' -RamMb ${var.services_vm_ram_mb} -Cpus ${var.services_vm_cpus}"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # 2. AD連携 & Linux ミドルウェア (DNS/Web/Mail) 一括プロビジョニング
  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\provision_services.ps1 -DomainName '${var.domain_name}' -AdDcIp '${var.ad_dc_ip}' -SrvIp '${var.services_vm_ip}' -LdapUser '${var.ldap_user}' -LdapPass '${var.ldap_pass}' -AdminUser '${var.ad_admin_user}' -AdminPass '${var.ad_admin_password}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }

  # 3. 破棄処理 (terraform destroy 時)
  provisioner "local-exec" {
    when        = destroy
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\destroy_vm.ps1 -VmName '${self.triggers.vm_name}' -VmsDir '${self.triggers.vms_dir}'"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }
}
