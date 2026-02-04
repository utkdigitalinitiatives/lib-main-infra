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

# Data source: Reference existing dev resource group (shared with dev environment)
data "azurerm_resource_group" "dev" {
  name = var.pr_number != null ? "lib-main-dev-pr-${var.pr_number}-rg" : "lib-main-dev-rg"
}

# Data source: Reference existing PostgreSQL from dev environment
data "azurerm_postgresql_flexible_server" "dev" {
  name                = var.pr_number != null ? "lib-main-pr-${var.pr_number}-psql" : "lib-main-dev-psql"
  resource_group_name = data.azurerm_resource_group.dev.name
}

# Test VM (second validation stage, uses same PostgreSQL as dev)
# Note: Dev VM should be destroyed before creating Test VM (sequential workflow)
module "test_vm" {
  source = "../../modules/drupal-dev-vm"

  environment          = "test"
  pr_number            = var.pr_number
  resource_group_name  = data.azurerm_resource_group.dev.name
  location             = data.azurerm_resource_group.dev.location
  subnet_id            = var.subnet_id
  source_image_id      = data.azurerm_shared_image_version.drupal.id
  vm_size              = var.vm_size
  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  assign_public_ip     = var.assign_public_ip

  # Pass database connection info via cloud-init (uses dev PostgreSQL)
  custom_data = templatefile("${path.module}/cloud-init.tftpl", {
    db_host     = data.azurerm_postgresql_flexible_server.dev.fqdn
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
