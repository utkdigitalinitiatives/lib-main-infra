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
#   6. After dev-review approval, developer merges dev → main
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

# Data source: Get image version from Azure Compute Gallery
data "azurerm_shared_image_version" "drupal" {
  name                = var.image_version
  image_name          = var.image_name
  gallery_name        = var.gallery_name
  resource_group_name = var.gallery_resource_group_name
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
    db_password     = var.db_admin_password
    hash_salt       = random_password.drupal_hash_salt.result
    storage_account = var.devtest_storage_account
    storage_key     = var.devtest_storage_key
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
