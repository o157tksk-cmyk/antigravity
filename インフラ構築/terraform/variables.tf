# ==============================================================================
# Terraform Variables Definition (variables.tf)
# ==============================================================================

variable "domain_name" {
  type        = string
  description = "Active Directory Domain Name (FQDN)"
  default     = "hogehoge.local"
}

variable "domain_netbios" {
  type        = string
  description = "Active Directory NetBIOS Name"
  default     = "HOGEHOGE"
}

variable "ad_dc_ip" {
  type        = string
  description = "Active Directory Domain Controller IP Address"
  default     = "192.168.10.10"
}

variable "ad_admin_user" {
  type        = string
  description = "Domain Administrator Username"
  default     = "Administrator"
}

variable "ad_admin_password" {
  type        = string
  description = "Domain Administrator Password"
  sensitive   = true
  default     = "P@ssw0rd2022!"
}

variable "dc01_vm_name" {
  type        = string
  description = "Primary Domain Controller VM Name"
  default     = "Win2022-DC01"
}

variable "dc01_ip" {
  type        = string
  description = "Primary Domain Controller Static IPv4"
  default     = "192.168.10.10"
}

variable "dc02_vm_name" {
  type        = string
  description = "Replica Domain Controller VM Name"
  default     = "Win2022-DC02"
}

variable "dc02_ip" {
  type        = string
  description = "Replica Domain Controller Static IPv4"
  default     = "192.168.10.11"
}

variable "dc_ram_mb" {
  type        = number
  description = "Domain Controller RAM in MB"
  default     = 4096
}

variable "dc_cpus" {
  type        = number
  description = "Domain Controller CPU core count"
  default     = 2
}

variable "win_master_vhdx_path" {
  type        = string
  description = "Windows Server 2022 Master Golden VHDX"
  default     = "C:\\HyperV\\Master\\Win2022-GoldenImage.vhdx"
}

variable "services_vm_name" {
  type        = string
  description = "Rocky Linux Services VM Name"
  default     = "Rocky9-AppSrv"
}

variable "services_vm_ip" {
  type        = string
  description = "Rocky Linux Static IPv4 Address"
  default     = "192.168.10.20"
}

variable "gateway_ip" {
  type        = string
  description = "Internal Network Gateway IP"
  default     = "192.168.10.1"
}

variable "prefix_length" {
  type        = number
  description = "Network Prefix Length"
  default     = 24
}

variable "services_vm_ram_mb" {
  type        = number
  description = "RAM size in MB for Rocky Linux VM"
  default     = 4096
}

variable "services_vm_cpus" {
  type        = number
  description = "CPU core count for Rocky Linux VM"
  default     = 2
}

variable "switch_name" {
  type        = string
  description = "Hyper-V Virtual Switch Name"
  default     = "LabInternalSwitch"
}

variable "master_vhdx_path" {
  type        = string
  description = "Absolute path to Rocky Linux Golden VHDX"
  default     = "C:\\HyperV\\Master\\Rocky9-Golden.vhdx"
}

variable "vms_dir" {
  type        = string
  description = "Hyper-V VMs root directory"
  default     = "C:\\HyperV\\VMs"
}

variable "ldap_user" {
  type        = string
  description = "LDAP Service Account Username"
  default     = "svc_ldap"
}

variable "ldap_pass" {
  type        = string
  description = "LDAP Service Account Password"
  sensitive   = true
  default     = "P@ssw0rd2022!"
}
