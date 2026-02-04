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
  description = "Address space for the VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_endpoints_prefix" {
  description = "Address prefix for private endpoints subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (e.g., ['0.0.0.0/0'] to allow all)"
  type        = list(string)
  default     = []
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
variable "vm_size" {
  description = "Size of the VM instances"
  type        = string
  default     = "Standard_B2s"
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
  default     = 32768  # 32 GB minimum
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

variable "db_admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
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
  default     = null  # If not provided, a random password will be generated
}

variable "drupal_site_uuid" {
  description = "Fixed Drupal site UUID for config sync. Must match config/sync/system.site.yml"
  type        = string
  # No default - must be provided for each site to ensure unique UUIDs
}
