# ------------------------------------------------------------------------------
# Dev Environment
# ------------------------------------------------------------------------------
# First stage of PR validation workflow. Creates ephemeral resources:
#   - Resource Group: lib-main-dev-pr-{number}-rg
#   - Dev VM: Single instance for initial validation
#
# Database is provided by the permanent devtest PostgreSQL instance,
# synced from production by the CI/CD workflow before deployment.
#
# Workflow:
#   1. lib-main repo pushes code → triggers repository_dispatch
#   2. Packer builds image with PR code
#   3. Production DB synced to devtest PostgreSQL
#   4. Dev environment deploys image for smoke tests
#   5. On success, dev environment is destroyed
#   6. DB re-synced, test environment deploys for integration tests
#   7. On PR close, cleanup workflow destroys remaining PR resources
#
# State isolation:
#   Each PR gets its own state file: dev/pr-{number}/terraform.tfstate
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
  # State key includes PR number for isolation: dev/pr-{number}/terraform.tfstate
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

# Resource group for dev resources (ephemeral per PR)
resource "azurerm_resource_group" "dev" {
  name     = var.pr_number != null ? "lib-main-dev-pr-${var.pr_number}-rg" : "lib-main-dev-rg"
  location = var.location

  tags = {
    Environment = "dev"
    PRNumber    = var.pr_number != null ? var.pr_number : "none"
    ManagedBy   = "terraform"
    Project     = "lib-main"
    Ephemeral   = var.pr_number != null ? "true" : "false"
  }
}

# Dev VM (first validation stage in PR workflow)
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
  }
}
