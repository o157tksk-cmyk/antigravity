# ==============================================================================
# Terraform Outputs (outputs.tf)
# ==============================================================================

output "active_directory_domain" {
  description = "Active Directory Domain FQDN"
  value       = var.domain_name
}

output "primary_dc" {
  description = "Primary Domain Controller (DC01)"
  value       = "${var.dc01_vm_name} (${var.dc01_ip})"
}

output "replica_dc" {
  description = "Replica Domain Controller (DC02)"
  value       = "${var.dc02_vm_name} (${var.dc02_ip})"
}

output "services_vm_name" {
  description = "Rocky Linux Services Virtual Machine Name"
  value       = var.services_vm_name
}

output "services_vm_ip" {
  description = "Rocky Linux Static IPv4 Address"
  value       = var.services_vm_ip
}

output "web_url" {
  description = "Web Server URL (Active Directory LDAP Auth)"
  value       = "http://${var.services_vm_ip}/ (FQDN: http://web.${var.domain_name}/)"
}

output "external_dns_server" {
  description = "External DNS Forwarder Server IP"
  value       = "${var.services_vm_ip}:53"
}

output "mail_server" {
  description = "Mail Server (Postfix / Dovecot)"
  value       = "mail.${var.domain_name} (SMTP: 25/587, IMAP: 143)"
}
