variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "pr_number" {
  description = "Pull request number for ephemeral environments"
  type        = string
  default     = null
}

# Image Gallery configuration
variable "gallery_name" {
  description = "Name of the Azure Compute Gallery"
  type        = string
}

variable "gallery_resource_group_name" {
  description = "Resource group containing the Azure Compute Gallery"
  type        = string
}

variable "image_name" {
  description = "Name of the image definition in the gallery"
  type        = string
  default     = "drupal-rocky-linux-9"
}

variable "image_version" {
  description = "Version of the image to deploy"
  type        = string
}

# Networking
variable "subnet_id" {
  description = "ID of the subnet where the VM will be deployed"
  type        = string
}

# VM configuration
variable "vm_size" {
  description = "Size of the VM instance"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "drupaladmin"
}

variable "admin_ssh_public_key" {
  description = "SSH public key for admin access"
  type        = string
}

variable "assign_public_ip" {
  description = "Assign a public IP address to the VM for testing access"
  type        = bool
  default     = true
}

# Database configuration (references permanent devtest PostgreSQL)
variable "devtest_db_host" {
  description = "FQDN of the permanent devtest PostgreSQL server"
  type        = string
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

# Blob storage configuration (references permanent devtest storage account)
variable "devtest_storage_account" {
  description = "Name of the permanent devtest storage account"
  type        = string
}

# Solr search backend (asimov AKS). The dev VM is in the production VNet, so it
# reaches Solr over the same private path as production — no new networking.
# Dev uses its own collection + scoped credential so it cannot touch the
# production index.
variable "solr_host" {
  description = "DNS hostname Drupal uses to reach Solr (resolved by the lib-main.internal private DNS zone shared with production)."
  type        = string
  default     = "solr.lib-main.internal"
}

variable "solr_port" {
  description = "Port Drupal uses to reach Solr."
  type        = string
  default     = "8983"
}

variable "solr_path" {
  description = "URL path prefix for Solr."
  type        = string
  default     = "/solr"
}

variable "solr_core" {
  description = "Solr collection backing the dev index. Separate from production's collection."
  type        = string
  default     = "mainsite_dev"
}

variable "solr_username" {
  description = "Solr basic-auth username scoped to the dev collection (mainsite_dev)."
  type        = string
  default     = "drupal-mainsite-dev"
}

variable "solr_password_secret_name" {
  description = "Key Vault secret holding the dev Solr connector password (owned by environments/devtest/)."
  type        = string
  default     = "dev-solr-drupal-mainsite-password"
}

variable "drupal_search_server_id" {
  description = "Drupal search_api.server.* config entity ID matched by environment.php overrides."
  type        = string
  default     = "solr_mainsite"
}

