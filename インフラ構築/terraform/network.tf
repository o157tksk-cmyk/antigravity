# ==============================================================================
# Hyper-V Network Switch Configuration (network.tf)
# ==============================================================================

resource "null_resource" "hyperv_switch" {
  triggers = {
    switch_name = var.switch_name
    gateway_ip  = var.gateway_ip
    prefix_len  = var.prefix_length
  }

  provisioner "local-exec" {
    command     = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\create_switch.ps1 -SwitchName '${var.switch_name}' -GatewayIp '${var.gateway_ip}' -PrefixLength ${var.prefix_length}"
    interpreter = ["powershell", "-NoProfile", "-Command"]
  }
}
