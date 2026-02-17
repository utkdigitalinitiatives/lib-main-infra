# ------------------------------------------------------------------------------
# Production Environment
# ------------------------------------------------------------------------------
# Deploys the complete lib-main Drupal application stack:
#   - Resource Group: lib-main-production-rg
#   - Networking: VNet, subnets, NSG with load balancer rules
#   - Load Balancer: Public Standard LB with health probes
#   - PostgreSQL: Flexible Server with 14-day backup retention
#   - Blob Storage: Media files accessed via S3Proxy
#   - VMSS: Single instance with rolling updates
#
# Deployment:
#   terraform init -backend-config="resource_group_name=lib-main-tfstate-rg" \
#     -backend-config="storage_account_name=<tfstate-storage-account>" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=production/terraform.tfstate"
#   terraform apply -var="image_version=1.0.0"
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

  # Remote backend for CI/CD - values provided via -backend-config
  # For local development, run: terraform init -backend=false
  # For CI/CD, run: terraform init -backend-config="resource_group_name=..." -backend-config="storage_account_name=..." ...
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  environment = "production"
  common_tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Application = "drupal"
    Project     = "lib-main"
    CostCenter  = "E016010"
  }
}

# Generate random hash salt for Drupal security
resource "random_password" "drupal_hash_salt" {
  length  = 64
  special = false
}

# Generate random Drupal admin password if not provided
# Use only shell-safe special characters to avoid escaping issues in cloud-init
resource "random_password" "drupal_admin" {
  length           = 24
  special          = true
  override_special = "!@#%^&*-_=+?"
}

# Resource group for all production resources
resource "azurerm_resource_group" "production" {
  name     = "lib-main-production-rg"
  location = var.location
  tags     = local.common_tags
}

# Data source: Get image version from Azure Compute Gallery
data "azurerm_shared_image_version" "drupal" {
  count               = var.use_gallery_image ? 1 : 0
  name                = var.image_version
  image_name          = var.image_name
  gallery_name        = var.gallery_name
  resource_group_name = var.gallery_resource_group_name
}

# Networking: VNet, subnets, NSG with Load Balancer rules
module "networking" {
  source = "../../modules/networking"

  environment                             = local.environment
  resource_group_name                     = azurerm_resource_group.production.name
  location                                = var.location
  vnet_address_space                      = var.vnet_address_space
  web_subnet_address_prefix               = var.web_subnet_prefix
  private_endpoints_subnet_address_prefix = var.private_endpoints_prefix
  enable_load_balancer_rules              = true
  enable_front_door_rules                 = false
  allowed_ssh_cidr_blocks                 = var.allowed_ssh_cidr_blocks

  tags = local.common_tags
}

# Load Balancer: Public Standard LB
module "load_balancer" {
  source = "../../modules/load-balancer"

  environment          = local.environment
  resource_group_name  = azurerm_resource_group.production.name
  location             = var.location
  dns_label            = var.public_ip_id == null ? var.lb_dns_label : null
  public_ip_id         = var.public_ip_id
  health_probe_path    = var.health_probe_path
  enable_https         = var.enable_https
  enable_outbound_rule = true

  tags = local.common_tags
}

# PostgreSQL: Flexible Server
module "postgresql" {
  source = "../../modules/postgresql"

  environment                  = local.environment
  resource_group_name          = azurerm_resource_group.production.name
  location                     = var.location
  sku_name                     = var.postgresql_sku
  storage_mb                   = var.postgresql_storage_mb
  administrator_login          = var.db_admin_username
  administrator_password       = var.db_admin_password
  database_name                = var.db_name
  postgresql_version           = var.postgresql_version
  backup_retention_days        = 14
  geo_redundant_backup_enabled = false
  allow_azure_services         = true

  # Public access - add your IP for management
  allowed_ip_addresses = var.db_allowed_ips

  tags = local.common_tags
}

# Blob Storage: Drupal media files
module "blob_storage" {
  source = "../../modules/blob-storage"

  environment                = local.environment
  resource_group_name        = azurerm_resource_group.production.name
  location                   = var.location
  container_name             = "drupal-media"
  replication_type           = "LRS"
  soft_delete_retention_days = 7
  enable_versioning          = false

  # Two-pass deployment: set false initially, true after VMSS exists
  enable_vmss_blob_access = var.enable_vmss_blob_access
  vmss_principal_id       = var.enable_vmss_blob_access ? module.vmss.vmss_identity_principal_id : null

  tags = local.common_tags
}

# TLS certificate storage container (certs persist across VMSS instance replacements)
resource "azurerm_storage_container" "tls_certs" {
  name                  = "tls-certs"
  storage_account_id    = module.blob_storage.storage_account_id
  container_access_type = "private"
}

# VMSS: Single instance with rolling updates
module "vmss" {
  source = "../../modules/drupal-vmss"

  environment         = local.environment
  resource_group_name = azurerm_resource_group.production.name
  location            = var.location
  subnet_id           = module.networking.web_subnet_id

  # Image source: gallery or marketplace fallback
  source_image_id = var.use_gallery_image ? data.azurerm_shared_image_version.drupal[0].id : null

  vm_size        = var.vm_size
  instance_count = 1
  min_instances  = 1
  max_instances  = 2

  admin_username       = var.admin_username
  admin_ssh_public_key = var.admin_ssh_public_key
  os_disk_size_gb      = var.os_disk_size_gb

  health_probe_path = var.health_probe_path
  health_probe_port = 80

  enable_autoscaling = false

  # Connect to Load Balancer
  load_balancer_backend_pool_id = module.load_balancer.backend_pool_id

  # Cloud-init with database, storage, and Drupal configuration
  custom_data = templatefile("${path.module}/cloud-init.tftpl", {
    db_host               = module.postgresql.fqdn
    db_name               = module.postgresql.database_name
    db_user               = var.db_admin_username
    db_password           = var.db_admin_password
    storage_account       = module.blob_storage.storage_account_name
    storage_container     = module.blob_storage.container_name
    storage_endpoint      = module.blob_storage.primary_blob_endpoint
    storage_key           = module.blob_storage.primary_access_key
    hash_salt             = random_password.drupal_hash_salt.result
    lb_fqdn               = module.load_balancer.public_ip_fqdn
    drupal_admin_password = var.drupal_admin_password != null ? var.drupal_admin_password : random_password.drupal_admin.result
    drupal_site_uuid      = var.drupal_site_uuid
    domain_name           = var.domain_name
    enable_https          = var.enable_https
  })

  tags = merge(local.common_tags, {
    ImageVersion = var.use_gallery_image ? var.image_version : "marketplace"
  })
}
