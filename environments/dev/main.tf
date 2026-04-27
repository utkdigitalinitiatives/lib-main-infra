# ------------------------------------------------------------------------------
# Dev Environment
# ------------------------------------------------------------------------------
# Shared dev environment for dev-branch validation. Creates:
#   - Resource Group: lib-main-dev-rg (shared, not per-PR)
#   - Dev VM: Single instance for validation
#
# Database is provided by the permanent devtest PostgreSQL instance,
# synced from production by the CI/CD workflow before deployment.
#
# Workflow:
#   1. Developer merges PR to dev branch in lib-main
#   2. Push to dev triggers repository_dispatch (drupal-dev-merge)
#   3. Packer builds image with dev branch code
#   4. Production DB synced to devtest PostgreSQL
#   5. Dev VM deployed with new image for validation
#   6. Developer merges dev → main
#   7. Push to main triggers production deploy and dev VM cleanup
#
# State: dev/terraform.tfstate (single shared state)
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

  # Backend configuration for Terraform state
  # Uses partial configuration - remaining values passed via -backend-config
  # State key: dev/terraform.tfstate (shared across dev deploys)
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# Random hash salt for Drupal security
resource "random_password" "drupal_hash_salt" {
  length  = 64
  special = true
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

# Allow the dev VM managed identity to read secrets from the shared vault at boot.
# The dev VM connects to the devtest PostgreSQL server, so it reads
# devtest-db-admin-password.
resource "azurerm_role_assignment" "dev_vm_kv_secrets_user" {
  scope                = data.terraform_remote_state.secrets.outputs.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.dev_vm.vm_identity_principal_id
}

# Persist the dev VM's hash salt to KV so it survives state churn.
resource "azurerm_key_vault_secret" "drupal_hash_salt" {
  name         = "dev-drupal-hash-salt"
  value        = random_password.drupal_hash_salt.result
  key_vault_id = data.terraform_remote_state.secrets.outputs.key_vault_id
  content_type = "text/plain"
}

# Data source: Get image version from Azure Compute Gallery
data "azurerm_shared_image_version" "drupal" {
  name                = var.image_version
  image_name          = var.image_name
  gallery_name        = var.gallery_name
  resource_group_name = var.gallery_resource_group_name
}

# SAS token for Apache reverse proxy to serve blob storage files (read-only, 2-year expiry)
data "azurerm_storage_account_sas" "media_read" {
  connection_string = "DefaultEndpointsProtocol=https;AccountName=${var.devtest_storage_account};AccountKey=${var.devtest_storage_key};EndpointSuffix=core.windows.net"
  https_only        = true
  start             = "2026-01-01T00:00:00Z"
  expiry            = "2028-01-01T00:00:00Z"

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

# Resource group for dev resources (shared or per-PR)
resource "azurerm_resource_group" "dev" {
  name     = var.pr_number != null ? "lib-main-dev-pr-${var.pr_number}-rg" : "lib-main-dev-rg"
  location = var.location

  tags = {
    Environment = "dev"
    PRNumber    = var.pr_number != null ? var.pr_number : "none"
    ManagedBy   = "terraform"
    Project     = "lib-main"
    Ephemeral   = var.pr_number != null ? "true" : "false"
    CostCenter  = "E016010"
  }
}

# Dev VM (validation stage)
module "dev_vm" {
  source = "../../modules/drupal-dev-vm"

  environment          = "dev"
  pr_number            = var.pr_number
  resource_group_name  = azurerm_resource_group.dev.name
  location             = var.location
  subnet_id            = var.subnet_id
  source_image_id      = data.azurerm_shared_image_version.drupal.id
  vm_size              = var.vm_size
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  assign_public_ip     = var.assign_public_ip

  # Pass database connection info via cloud-init (uses permanent devtest PostgreSQL)
  custom_data = templatefile("${path.module}/cloud-init.tftpl", {
    db_host         = var.devtest_db_host
    db_name         = var.db_name
    db_user         = var.db_admin_username
    kv_name         = data.terraform_remote_state.secrets.outputs.key_vault_name
    env_name        = "devtest"
    hash_salt_secret_name = azurerm_key_vault_secret.drupal_hash_salt.name
    storage_account   = var.devtest_storage_account
    storage_key       = var.devtest_storage_key
    # Escape % so mod_rewrite doesn't interpret %2B / %2F / %3D as backreferences (%N).
    # The escaped \% becomes a literal % in the substitution; combined with [NE] flag
    # in the RewriteRule and proxy-nocanon env, the SAS reaches Azure verbatim.
    storage_sas_token = replace(data.azurerm_storage_account_sas.media_read.sas, "%", "\\%")
  })

  tags = {
    Environment  = "dev"
    PRNumber     = var.pr_number != null ? var.pr_number : "none"
    Project      = "lib-main"
    Stage        = "dev-validation"
    ImageVersion = var.image_version
    CostCenter   = "E016010"
  }
}
