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
  # Use PR number in name if provided, otherwise use environment
  name_suffix = var.pr_number != null ? "pr-${var.pr_number}" : var.environment
  name_prefix = "drupal-dev-${local.name_suffix}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    PRNumber    = var.pr_number
    ManagedBy   = "terraform"
    Application = "drupal"
    Ephemeral   = "true"
  })
}

# Public IP (optional, for direct access during testing)
resource "azurerm_public_ip" "dev" {
  count = var.assign_public_ip ? 1 : 0

  name                = "${local.name_prefix}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

# Network Interface
resource "azurerm_network_interface" "dev" {
  name                = "${local.name_prefix}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.assign_public_ip ? azurerm_public_ip.dev[0].id : null
  }

  tags = local.common_tags
}

# Associate NIC with Application Security Groups
resource "azurerm_network_interface_application_security_group_association" "dev" {
  for_each = toset(var.application_security_group_ids)

  network_interface_id          = azurerm_network_interface.dev.id
  application_security_group_id = each.value
}

# Linux Virtual Machine for Dev/Test
resource "azurerm_linux_virtual_machine" "dev" {
  name                = "${local.name_prefix}-vm"
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.dev.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  # Custom image from gallery (if provided) or marketplace fallback
  source_image_id = var.source_image_id

  # Rocky Linux 9 marketplace image (fallback when source_image_id is null)
  dynamic "source_image_reference" {
    for_each = var.source_image_id == null ? [1] : []
    content {
      publisher = "resf"
      offer     = "rockylinux-x86_64"
      sku       = "9-base"
      version   = "latest"
    }
  }

  # Marketplace plan (required for marketplace image or gallery images built from marketplace)
  dynamic "plan" {
    for_each = var.source_image_id == null || var.use_marketplace_plan ? [1] : []
    content {
      name      = "9-base"
      product   = "rockylinux-x86_64"
      publisher = "resf"
    }
  }

  os_disk {
    name                 = "${local.name_prefix}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  # Custom data for cloud-init (Ansible preparation, etc.)
  custom_data = var.custom_data != null ? base64encode(var.custom_data) : null

  # Identity for Azure resource access (e.g., Key Vault, Blob Storage)
  identity {
    type = "SystemAssigned"
  }

  # Boot diagnostics with managed storage
  dynamic "boot_diagnostics" {
    for_each = var.enable_boot_diagnostics ? [1] : []
    content {}
  }

  tags = local.common_tags
}
