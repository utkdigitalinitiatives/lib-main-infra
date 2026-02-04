terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }
}

locals {
  gallery_name = "${var.name_prefix}-gallery"
  common_tags = merge(var.tags, {
    ManagedBy   = "terraform"
    Application = "drupal"
  })
}

# Azure Compute Gallery for Drupal images
resource "azurerm_shared_image_gallery" "drupal" {
  name                = replace(local.gallery_name, "-", "_")
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Drupal application images built with Packer"

  tags = local.common_tags
}

# Image Definition for Drupal Rocky Linux 9
resource "azurerm_shared_image" "drupal" {
  name                = var.image_definition_name
  gallery_name        = azurerm_shared_image_gallery.drupal.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  hyper_v_generation  = "V2"
  architecture        = "x64"

  identifier {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
  }

  # Recommended specs for Drupal workloads
  min_recommended_vcpu_count   = 2
  max_recommended_vcpu_count   = 16
  min_recommended_memory_in_gb = 4
  max_recommended_memory_in_gb = 64

  tags = local.common_tags
}
