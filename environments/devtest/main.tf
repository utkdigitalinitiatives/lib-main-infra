# ------------------------------------------------------------------------------
# DevTest Environment
# ------------------------------------------------------------------------------
# Permanent infrastructure shared across all PR pipelines:
#   - Resource Group: lib-main-devtest-rg
#   - PostgreSQL: Burstable instance synced from production before each stage
#   - Automation: Weekly auto-stop to manage costs
#
# This environment is deployed once and persists across PRs.
# The database is synced from production by the CI/CD workflow
# before each dev/test stage, so each stage gets a fresh copy
# of production data.
#
# State key: devtest/terraform.tfstate
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

locals {
  environment = "devtest"
  common_tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "lib-main"
    CostCenter  = "E016010"
  }
}

resource "azurerm_resource_group" "devtest" {
  name     = "lib-main-devtest-rg"
  location = var.location
  tags     = local.common_tags
}

module "postgresql" {
  source = "../../modules/postgresql"

  environment            = local.environment
  resource_group_name    = azurerm_resource_group.devtest.name
  location               = var.location
  sku_name               = "B_Standard_B1ms"
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  database_name          = var.db_name
  backup_retention_days  = 7
  allow_azure_services   = true

  tags = merge(local.common_tags, {
    AutoStop = "true"
  })
}

module "blob_storage" {
  source = "../../modules/blob-storage"

  environment                = local.environment
  resource_group_name        = azurerm_resource_group.devtest.name
  location                   = var.location
  container_name             = "drupal-media"
  replication_type           = "LRS"
  soft_delete_retention_days = 7
  enable_versioning          = false

  tags = local.common_tags
}

module "automation" {
  source = "../../modules/azure-automation"

  environment         = local.environment
  resource_group_name = azurerm_resource_group.devtest.name
  location            = var.location

  tags = local.common_tags
}
