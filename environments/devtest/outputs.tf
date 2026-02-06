output "resource_group_name" {
  description = "Name of the devtest resource group"
  value       = azurerm_resource_group.devtest.name
}

output "postgresql_fqdn" {
  description = "Fully qualified domain name of the devtest PostgreSQL server"
  value       = module.postgresql.fqdn
}

output "postgresql_server_name" {
  description = "Name of the devtest PostgreSQL server"
  value       = module.postgresql.server_name
}

output "postgresql_database_name" {
  description = "Name of the Drupal database"
  value       = module.postgresql.database_name
}

output "automation_account_name" {
  description = "Name of the Automation Account"
  value       = module.automation.automation_account_name
}
