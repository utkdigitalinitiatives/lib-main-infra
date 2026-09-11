variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

# Image Gallery configuration
variable "use_gallery_image" {
  description = "Use image from Azure Compute Gallery (false uses marketplace Rocky Linux)"
  type        = bool
  default     = false
}

variable "gallery_name" {
  description = "Name of the Azure Compute Gallery"
  type        = string
  default     = ""
}

variable "gallery_resource_group_name" {
  description = "Resource group containing the Azure Compute Gallery"
  type        = string
  default     = ""
}

variable "image_name" {
  description = "Name of the image definition in the gallery"
  type        = string
  default     = "drupal-rocky-linux-9"
}

variable "image_version" {
  description = "Version of the image to deploy (e.g., 1.0.0)"
  type        = string
  default     = "1.0.0"
}

# Networking
variable "vnet_address_space" {
  description = "Address space for the VNet (10.20.0.0/16 is reserved for lib-main in the mccarthy-infra allocation table; 10.0.0.0/16 collides with the Asimov AKS service CIDR)"
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_endpoints_prefix" {
  description = "Address prefix for private endpoints subnet"
  type        = string
  default     = "10.20.2.0/24"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default = [
    "160.36.0.0/16",   # UTK campus wired
    "10.65.0.0/16",    # UTK VPN
    "10.46.0.0/15",    # UTK mod1 (10.46.x.x and 10.47.x.x)
    "216.96.128.0/17", # UTK eduroam
    "192.249.1.0/24",  # UTK campus (new range, verify exact CIDR)
  ]
}

# Load Balancer
variable "lb_dns_label" {
  description = "DNS label for Load Balancer public IP (creates <label>.<region>.cloudapp.azure.com)"
  type        = string
  default     = null
}

variable "enable_https" {
  description = "Enable HTTPS on the Load Balancer"
  type        = bool
  default     = false
}

variable "health_probe_path" {
  description = "Path for health probe endpoint"
  type        = string
  default     = "/health"
}

# VM configuration
# Burstable v2 (Basv2). Was Standard_B2s (Bs v1), which Azure has placed under
# capacity growth restrictions from 2026-07-31 and retirement on 2028-07-31.
# Standard_B2als_v2 is the same 2 vCPU / 4 GiB at a slightly lower rate.
# Longer term this moves to a D-class size (Standard_D2as_v5).
variable "vm_size" {
  description = "Size of the VM instances"
  type        = string
  default     = "Standard_B2als_v2"
}

variable "admin_username" {
  description = "Admin username for the VMs"
  type        = string
  default     = "drupaladmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for admin access"
  type        = string
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 64
}

# PostgreSQL configuration
variable "postgresql_sku" {
  description = "SKU for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768 # 32 GB minimum
}

variable "postgresql_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "db_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "drupaladmin"
}

variable "db_name" {
  description = "Name of the Drupal database"
  type        = string
  default     = "drupal"
}

variable "db_allowed_ips" {
  description = "List of IP addresses allowed to connect to PostgreSQL"
  type        = list(string)
  default     = []
}

# Blob Storage configuration
variable "enable_vmss_blob_access" {
  description = "Enable VMSS blob access role assignment. Set false for initial deployment, true after VMSS exists."
  type        = bool
  default     = false
}

# Drupal configuration
variable "drupal_admin_password" {
  description = "Password for the Drupal admin user"
  type        = string
  sensitive   = true
  default     = null # If not provided, a random password will be generated
}

variable "drupal_site_uuid" {
  description = "Fixed Drupal site UUID for config sync. Must match config/system.site.yml"
  type        = string
  # No default - must be provided for each site to ensure unique UUIDs
}

variable "domain_name" {
  description = "Domain name for TLS certificate (e.g., libdev1.lib.utk.edu)"
  type        = string
  default     = null
}

variable "public_ip_id" {
  description = "Existing Azure public IP resource ID for the Load Balancer. If null, a new IP is created."
  type        = string
  default     = null
}

# Solr / asimov AKS integration
variable "asimov_vnet_name" {
  description = "Name of the asimov AKS VNet to peer with."
  type        = string
  default     = "aks-vnet-36013409"
}

variable "asimov_vnet_resource_group" {
  description = "Resource group containing the asimov AKS VNet (the AKS node resource group)."
  type        = string
  default     = "MC_rg-asimov_Asimov_eastus2"
}

variable "asimov_eso_principal_id" {
  description = <<EOT
Object ID (principalId, NOT clientId) of the asimov External Secrets Operator user-assigned managed identity. Granted Key Vault Secrets User on the shared vault so ESO can sync Solr passwords into the cluster.

Lookup:
  az identity show --resource-group rg-asimov --name id-asimov-eso --query principalId -o tsv
EOT
  type        = string
}

variable "solr_internal_lb_ip" {
  description = "Pinned private IP for the Solr internal Azure LB inside the asimov AKS VNet. Must be free and inside the AKS VNet address space."
  type        = string
  default     = "10.224.255.10"
}

variable "solr_host" {
  description = "DNS hostname Drupal uses to reach Solr. Resolved by the search.utklib.internal private DNS zone to solr_internal_lb_ip."
  type        = string
  default     = "solr.search.utklib.internal"
}

variable "solr_port" {
  description = "Port Drupal uses to reach Solr."
  type        = string
  default     = "8983"
}

variable "solr_path" {
  description = "URL path prefix for Solr (search_api connector setting)."
  type        = string
  default     = "/"
}

variable "solr_core" {
  description = "Solr collection backing the production index. Must match the security.json collection glob (mainsite_*) or queries return 403."
  type        = string
  default     = "mainsite_prod"
}

variable "solr_username" {
  description = "Solr basic-auth username scoped to the production collection (mainsite_prod)."
  type        = string
  default     = "drupal-mainsite-prod"
}

variable "drupal_search_server_id" {
  description = "Drupal search_api.server.* config entity ID matched by environment.php overrides."
  type        = string
  default     = "solr_mainsite"
}
