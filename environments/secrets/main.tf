# ------------------------------------------------------------------------------
# Secrets Environment
# ------------------------------------------------------------------------------
# Provisions a single shared Azure Key Vault used by production + devtest.
# Lives in its own resource group (lib-main-secrets-rg) so its lifecycle is
# decoupled from any application environment.
#
# Application envs consume the vault via `data "azurerm_key_vault"` and grant
# their own VMSS managed identities Key Vault Secrets User at vault scope.
#
# Deployment:
#   terraform init -backend-config="resource_group_name=lib-main-tfstate-rg" \
#     -backend-config="storage_account_name=libmaintfstate5a6e642c" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=secrets/terraform.tfstate"
#   terraform apply
#
# State key: secrets/terraform.tfstate
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_deleted_secrets_on_destroy = true
      recover_soft_deleted_secrets          = true
    }
  }
  subscription_id = var.subscription_id
}

locals {
  environment = "secrets"
  common_tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "lib-main"
    CostCenter  = "E016010"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "secrets" {
  name     = "lib-main-secrets-rg"
  location = var.location
  tags     = local.common_tags
}

# Random suffix keeps the vault name globally unique without depending on a hand-picked value.
resource "random_id" "kv_suffix" {
  byte_length = 4
}

resource "azurerm_key_vault" "shared" {
  name                = "lib-main-kv-${random_id.kv_suffix.hex}"
  location            = azurerm_resource_group.secrets.location
  resource_group_name = azurerm_resource_group.secrets.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # Network ACLs intentionally permissive: RBAC is the primary authn boundary.
  # GitHub-hosted runner egress IPs change frequently, and locking ip_rules to
  # them creates ongoing maintenance. Tightening is tracked as a follow-up TODO
  # (subnet allowlist via Microsoft.KeyVault service endpoint on the web subnet).
  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  tags = local.common_tags
}

# GitHub Actions service principal: needs to set + read secrets during apply
# and read for pg_dump/pg_restore. Object ID (not app/client ID) required.
resource "azurerm_role_assignment" "gh_actions_secrets_officer" {
  scope                = azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.gh_actions_sp_object_id
}

# Operators: full read/write on secrets for manual rotation and troubleshooting.
resource "azurerm_role_assignment" "operator_secrets_officer" {
  for_each             = toset(var.operator_object_ids)
  scope                = azurerm_key_vault.shared.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}
