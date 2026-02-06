# ------------------------------------------------------------------------------
# Test Environment
# ------------------------------------------------------------------------------
# Second stage of PR validation workflow. Creates its own ephemeral resources:
#   - Resource Group: lib-main-test-pr-{number}-rg
#   - Test VM: Fresh instance for integration testing
#
# Database is provided by the permanent devtest PostgreSQL instance,
# re-synced from production by the CI/CD workflow before deployment.
#
# Workflow:
#   1. Dev stage completes successfully and is destroyed
#   2. Production DB re-synced to devtest PostgreSQL
#   3. Test VM created in its own resource group
#   4. Integration tests run against test VM
#   5. On success, PR ready for manual approval
#   6. On PR close, cleanup workflow destroys test resources
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }

  # Backend configuration for Terraform state
  # Uses partial configuration - remaining values passed via -backend-config
  # State key includes PR number for isolation: test/pr-{number}/terraform.tfstate
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# Data source: Get image version from Azure Compute Gallery
data "azurerm_shared_image_version" "drupal" {
  name                = var.image_version
  image_name          = var.image_name
  gallery_name        = var.gallery_name
  resource_group_name = var.gallery_resource_group_name
}

# Resource group for test resources (ephemeral per PR)
resource "azurerm_resource_group" "test" {
  name     = var.pr_number != null ? "lib-main-test-pr-${var.pr_number}-rg" : "lib-main-test-rg"
  location = var.location

  tags = {
    Environment = "test"
    PRNumber    = var.pr_number != null ? var.pr_number : "none"
    ManagedBy   = "terraform"
    Project     = "lib-main"
    Ephemeral   = var.pr_number != null ? "true" : "false"
  }
}

# Test VM (second validation stage, uses permanent devtest PostgreSQL)
module "test_vm" {
  source = "../../modules/drupal-dev-vm"

  environment          = "test"
  pr_number            = var.pr_number
  resource_group_name  = azurerm_resource_group.test.name
  location             = var.location
  subnet_id            = var.subnet_id
  source_image_id      = data.azurerm_shared_image_version.drupal.id
  vm_size              = var.vm_size
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  assign_public_ip     = var.assign_public_ip

  # Pass database connection info via cloud-init (uses permanent devtest PostgreSQL)
  custom_data = templatefile("${path.module}/cloud-init.tftpl", {
    db_host     = var.devtest_db_host
    db_name     = var.db_name
    db_user     = var.db_admin_username
    db_password = var.db_admin_password
  })

  tags = {
    Environment  = "test"
    PRNumber     = var.pr_number != null ? var.pr_number : "none"
    Project      = "lib-main"
    Stage        = "test-validation"
    ImageVersion = var.image_version
  }
}
