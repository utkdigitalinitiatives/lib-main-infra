variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
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
