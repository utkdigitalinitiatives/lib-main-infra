variable "environment" {
  description = "Environment name (dev, test)"
  type        = string
}

variable "pr_number" {
  description = "Pull request number for ephemeral environments"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "SKU for PostgreSQL Flexible Server (Burstable tier recommended for dev/test)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB (minimum 32768 = 32 GB)"
  type        = number
  default     = 32768
}

variable "administrator_login" {
  description = "Administrator login username"
  type        = string
  default     = "drupaladmin"
}

variable "administrator_password" {
  description = "Administrator login password"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Name of the Drupal database"
  type        = string
  default     = "drupal"
}

variable "availability_zone" {
  description = "Availability zone for the server (null for no zone preference)"
  type        = string
  default     = null
}

variable "allowed_ip_addresses" {
  description = "List of individual IP addresses allowed to connect"
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Map of IP ranges allowed to connect (name => {start, end})"
  type = map(object({
    start = string
    end   = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
