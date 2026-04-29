# ------------------------------------------------------------------------------
# DevTest Environment — Persistent backing services for environments/dev/
# ------------------------------------------------------------------------------
# What this stack owns (all in lib-main-devtest-rg):
#   - PostgreSQL Flexible Server: drupal-devtest-psql (Burstable B1ms)
#   - Blob storage account:       drupaldevtest05q0a0t6 (drupal-media container)
#   - Automation Account:         lib-main-devtest-automation (weekly auto-stop)
#
# Lifecycle: applied manually, set-and-forget. These resources persist
# indefinitely and are NOT touched by any CI/CD workflow.
#
# Consumer: environments/dev/ (the ephemeral dev VM) connects to the PostgreSQL
# server above and reads its storage account key from Key Vault. This stack
# writes `devtest-storage-account-key` to KV for that purpose.
#
# Database refresh: the dev-merge workflow runs pg_dump from production and
# pg_restore into this server before each dev VM deploy.
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

# Shared Key Vault provisioned by environments/secrets/.
data "terraform_remote_state" "secrets" {
  backend = "azurerm"
  config = {
    resource_group_name  = "lib-main-tfstate-rg"
    storage_account_name = "libmaintfstate5a6e642c"
    container_name       = "tfstate"
    key                  = "secrets/terraform.tfstate"
  }
}

data "azurerm_key_vault_secret" "db_admin_password" {
  name         = "devtest-db-admin-password"
  key_vault_id = data.terraform_remote_state.secrets.outputs.key_vault_id
}

# Mirror the devtest storage account access key into KV. Consumed by the dev
# VM env (environments/dev/) via a data source, so the dev workflow no longer
# needs `az storage account keys list` at runtime.
resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "devtest-storage-account-key"
  value        = module.blob_storage.primary_access_key
  key_vault_id = data.terraform_remote_state.secrets.outputs.key_vault_id
  content_type = "text/plain"
}

module "postgresql" {
  source = "../../modules/postgresql"

  environment            = local.environment
  resource_group_name    = azurerm_resource_group.devtest.name
  location               = var.location
  sku_name               = "B_Standard_B1ms"
  administrator_login    = var.db_admin_username
  administrator_password = data.azurerm_key_vault_secret.db_admin_password.value
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

  # Per-developer isolated media containers + RBAC for azcopy sync.
  # AAD object IDs collected via: az ad user show --id <email> --query id -o tsv
  developer_identities = {
    aalbro   = "9d4c8253-5a4c-4688-bc17-4f234e1574bc"
    dshaw11  = "c240b11c-3d92-427f-8dda-417ba2ea94b3"
    mcheeti1 = "b8259997-975d-4b87-b799-87caab129a51"
    wveale   = "24511b84-14e4-4dc5-bba4-19e4b7a4a1b0"
  }

  tags = local.common_tags
}

module "automation" {
  source = "../../modules/azure-automation"

  environment         = local.environment
  resource_group_name = azurerm_resource_group.devtest.name
  location            = var.location

  tags = local.common_tags
}
