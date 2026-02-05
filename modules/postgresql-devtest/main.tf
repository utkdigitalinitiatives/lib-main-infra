# ------------------------------------------------------------------------------
# PostgreSQL Dev/Test Module
# ------------------------------------------------------------------------------
# Creates an ephemeral PostgreSQL Flexible Server for PR validation:
#   - Burstable tier (B1ms) for cost efficiency
#   - Public network access with firewall rules for CI/CD
#   - Minimal backup retention (7 days)
#   - No geo-redundancy or high availability
#   - Named with PR number for isolation (lib-main-pr-{number}-psql)
#
# Lifecycle:
#   Created when PR is opened, destroyed when PR is closed.
#   Shared between dev and test stages within the same PR workflow.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }
}

locals {
  name_suffix = var.pr_number != null ? "pr-${var.pr_number}" : var.environment
  server_name = "lib-main-${local.name_suffix}-psql"
  common_tags = merge(var.tags, {
    Environment = var.environment
    PRNumber    = var.pr_number != null ? var.pr_number : "none"
    ManagedBy   = "terraform"
    Ephemeral   = "true"
    Project     = "lib-main"
  })
}

# PostgreSQL Flexible Server (Burstable tier for dev/test)
resource "azurerm_postgresql_flexible_server" "devtest" {
  name                = local.server_name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgresql_version

  # Burstable tier for cost efficiency in dev/test
  sku_name   = var.sku_name
  storage_mb = var.storage_mb

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  # Public access for CI/CD (secured via firewall rules)
  public_network_access_enabled = true

  # Minimal backup for ephemeral instance
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Zone redundancy not needed for dev/test
  zone = var.availability_zone

  tags = local.common_tags
}

# Firewall rule: Allow Azure services (for CI/CD runners and other Azure resources)
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name      = "AllowAzureServices"
  server_id = azurerm_postgresql_flexible_server.devtest.id

  # Special range that allows all Azure services
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Firewall rules: Allow specific CI/CD IP addresses
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  for_each = { for idx, ip in var.allowed_ip_addresses : idx => ip }

  name      = "AllowIP-${each.key}"
  server_id = azurerm_postgresql_flexible_server.devtest.id

  start_ip_address = each.value
  end_ip_address   = each.value
}

# Firewall rules: Allow IP ranges (for VPN, office, etc.)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ranges" {
  for_each = var.allowed_ip_ranges

  name      = "AllowRange-${each.key}"
  server_id = azurerm_postgresql_flexible_server.devtest.id

  start_ip_address = each.value.start
  end_ip_address   = each.value.end
}

# Database for Drupal
resource "azurerm_postgresql_flexible_server_database" "drupal" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.devtest.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Enable pg_trgm extension (required by Drupal 11)
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.devtest.id
  value     = "PG_TRGM"
}
