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
  name_prefix = "drupal-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Application = "drupal"
  })
}

# Public IP for the Load Balancer
resource "azurerm_public_ip" "lb" {
  name                = "${local.name_prefix}-lb-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"

  # Optional: DNS label for easy access
  domain_name_label = var.dns_label != null ? var.dns_label : null

  tags = local.common_tags
}

# Standard Load Balancer
resource "azurerm_lb" "main" {
  name                = "${local.name_prefix}-lb"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = local.common_tags
}

# Backend Address Pool for VMSS
resource "azurerm_lb_backend_address_pool" "vmss" {
  name            = "vmss-backend-pool"
  loadbalancer_id = azurerm_lb.main.id
}

# Health Probe - HTTP
resource "azurerm_lb_probe" "http" {
  name                = "http-health-probe"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Http"
  port                = var.health_probe_port
  request_path        = var.health_probe_path
  interval_in_seconds = var.health_probe_interval
  number_of_probes    = var.health_probe_threshold
}

# Health Probe - HTTPS (optional, for when TLS is terminated at VMSS)
resource "azurerm_lb_probe" "https" {
  count = var.enable_https ? 1 : 0

  name                = "https-health-probe"
  loadbalancer_id     = azurerm_lb.main.id
  protocol            = "Https"
  port                = 443
  request_path        = var.health_probe_path
  interval_in_seconds = var.health_probe_interval
  number_of_probes    = var.health_probe_threshold
}

# Load Balancing Rule - HTTP
resource "azurerm_lb_rule" "http" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vmss.id]
  probe_id                       = azurerm_lb_probe.http.id
  tcp_reset_enabled               = true
  idle_timeout_in_minutes        = var.idle_timeout_minutes

  # Disable outbound SNAT - recommended for production
  disable_outbound_snat = true
}

# Load Balancing Rule - HTTPS (optional)
resource "azurerm_lb_rule" "https" {
  count = var.enable_https ? 1 : 0

  name                           = "https-rule"
  loadbalancer_id                = azurerm_lb.main.id
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.vmss.id]
  probe_id                       = azurerm_lb_probe.https[0].id
  tcp_reset_enabled               = true
  idle_timeout_in_minutes        = var.idle_timeout_minutes

  disable_outbound_snat = true
}

# Outbound Rule for VMSS instances to access internet (e.g., for package updates)
resource "azurerm_lb_outbound_rule" "vmss" {
  count = var.enable_outbound_rule ? 1 : 0

  name                    = "vmss-outbound-rule"
  loadbalancer_id         = azurerm_lb.main.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.vmss.id

  frontend_ip_configuration {
    name = "PublicIPAddress"
  }
}
