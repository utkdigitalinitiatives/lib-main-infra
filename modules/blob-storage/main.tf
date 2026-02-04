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
  # Storage account names must be 3-24 chars, lowercase alphanumeric only
  storage_account_name = var.storage_account_name != null ? var.storage_account_name : "drupal${var.environment}${random_string.suffix[0].result}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Application = "drupal"
  })
}

# Random suffix for storage account name uniqueness (only if name not provided)
resource "random_string" "suffix" {
  count   = var.storage_account_name == null ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

# Storage Account
resource "azurerm_storage_account" "drupal" {
  name                = local.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = var.shared_access_key_enabled

  # Network rules (optional private access)
  dynamic "network_rules" {
    for_each = var.enable_network_rules ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      ip_rules                   = var.allowed_ip_addresses
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  # Blob properties
  blob_properties {
    versioning_enabled = var.enable_versioning

    dynamic "delete_retention_policy" {
      for_each = var.soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.soft_delete_retention_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_retention_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_retention_days
      }
    }
  }

  tags = local.common_tags
}

# Blob container for Drupal media files
resource "azurerm_storage_container" "media" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.drupal.id
  container_access_type = "private"
}

# Role assignment: Allow VMSS managed identity to access blobs
resource "azurerm_role_assignment" "vmss_blob_contributor" {
  count                = var.enable_vmss_blob_access ? 1 : 0
  scope                = azurerm_storage_account.drupal.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.vmss_principal_id
}

# Optional: Additional role assignments for other identities
resource "azurerm_role_assignment" "additional_blob_access" {
  for_each             = var.additional_principal_ids
  scope                = azurerm_storage_account.drupal.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

# Private endpoint (optional, for production)
resource "azurerm_private_endpoint" "blob" {
  count               = var.private_endpoint_subnet_id != null ? 1 : 0
  name                = "${local.storage_account_name}-blob-pe"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${local.storage_account_name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.drupal.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = local.common_tags
}
