variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "drupal"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "image_definition_name" {
  description = "Name for the image definition"
  type        = string
  default     = "drupal-rocky-linux-9"
}

variable "image_publisher" {
  description = "Publisher name for image definition identifier"
  type        = string
  default     = "DrupalOrg"
}

variable "image_offer" {
  description = "Offer name for image definition identifier"
  type        = string
  default     = "drupal-rocky"
}

variable "image_sku" {
  description = "SKU for image definition identifier (e.g., 9-php83)"
  type        = string
  default     = "9-php83"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
