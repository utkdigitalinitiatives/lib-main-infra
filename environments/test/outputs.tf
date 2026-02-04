output "resource_group_name" {
  description = "Name of the dev resource group (shared)"
  value       = data.azurerm_resource_group.dev.name
}

# VM outputs
output "vm_id" {
  description = "ID of the test VM"
  value       = module.test_vm.vm_id
}

output "vm_name" {
  description = "Name of the test VM"
  value       = module.test_vm.vm_name
}

output "private_ip_address" {
  description = "Private IP address of the test VM"
  value       = module.test_vm.private_ip_address
}

output "public_ip_address" {
  description = "Public IP address of the test VM"
  value       = module.test_vm.public_ip_address
}

output "ssh_connection_string" {
  description = "SSH connection command for the test VM"
  value       = module.test_vm.ssh_connection_string
}

output "vm_identity_principal_id" {
  description = "Principal ID of the VM's managed identity"
  value       = module.test_vm.vm_identity_principal_id
}

# PostgreSQL outputs (from dev environment)
output "postgresql_fqdn" {
  description = "Fully qualified domain name of PostgreSQL server (from dev)"
  value       = data.azurerm_postgresql_flexible_server.dev.fqdn
}

output "postgresql_server_name" {
  description = "Name of the PostgreSQL server (from dev)"
  value       = data.azurerm_postgresql_flexible_server.dev.name
}

# Image outputs
output "image_version" {
  description = "Image version deployed to VM"
  value       = var.image_version
}

output "image_id" {
  description = "Full image ID from gallery"
  value       = data.azurerm_shared_image_version.drupal.id
}
