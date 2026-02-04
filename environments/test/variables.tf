variable "pr_number" {
  description = "Pull request number (must match dev environment)"
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

# Database configuration (references dev PostgreSQL)
variable "db_admin_username" {
  description = "PostgreSQL administrator username (same as dev)"
  type        = string
  default     = "drupaladmin"
}

variable "db_admin_password" {
  description = "PostgreSQL administrator password (same as dev)"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the Drupal database"
  type        = string
  default     = "drupal"
}
