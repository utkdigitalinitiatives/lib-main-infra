# lib-main Dev Environment
# Ephemeral resources for PR validation (first stage)
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
  # State key includes PR number for isolation: dev/pr-{number}/terraform.tfstate
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

# Ephemeral PostgreSQL for dev/test (created per PR)
module "postgresql" {
  source = "../../modules/postgresql-devtest"

  environment            = "dev"
  pr_number              = var.pr_number
  resource_group_name    = azurerm_resource_group.dev.name
  location               = var.location
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  database_name          = var.db_name
  sku_name               = var.db_sku_name
  allowed_ip_addresses   = var.db_allowed_ip_addresses

  tags = {
    Environment = "dev"
    PRNumber    = var.pr_number != null ? var.pr_number : "none"
    Project     = "lib-main"
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

  # Pass database connection info via cloud-init
  custom_data = templatefile("${path.module}/cloud-init.tftpl", {
    db_host     = module.postgresql.fqdn
    db_name     = module.postgresql.database_name
    db_user     = module.postgresql.administrator_login
    db_password = var.db_admin_password
  })

  tags = {
    Environment  = "dev"
    PRNumber     = var.pr_number != null ? var.pr_number : "none"
    Project      = "lib-main"
    Stage        = "dev-validation"
    ImageVersion = var.image_version
  }

  depends_on = [module.postgresql]
}
