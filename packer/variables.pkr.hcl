# Authentication
#
# Builds authenticate through the Azure CLI session: `azure/login` establishes it
# from a GitHub OIDC token in CI, `az login` locally. There is deliberately no
# client_secret variable - the CI service principal has no password to pass.
variable "use_azure_cli_auth" {
  description = "Use the ambient Azure CLI session (established by azure/login via OIDC in CI)"
  type        = bool
  default     = true
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# Gallery configuration
variable "gallery_resource_group_name" {
  description = "Resource group containing the Shared Image Gallery"
  type        = string
}

variable "gallery_name" {
  description = "Name of the Shared Image Gallery"
  type        = string
}

variable "image_name" {
  description = "Name of the image definition in the gallery"
  type        = string
  default     = "drupal-rocky-linux-9"
}

variable "image_version" {
  description = "Version of the image to create (e.g., 1.0.0, 2024.01.15)"
  type        = string
}

# Base image configuration (for two-tier image strategy)
variable "base_image_name" {
  description = "Name of the base image definition in the gallery"
  type        = string
  default     = "drupal-base-rocky-linux-9"
}

variable "base_image_version" {
  description = "Version of the base image to use (e.g., 2025.01.0)"
  type        = string
  default     = "2025.01.0"
}

variable "replication_regions" {
  description = "Regions to replicate the image to"
  type        = list(string)
  default     = ["eastus2"]
}

# Build VM configuration
variable "location" {
  description = "Azure region for the build VM"
  type        = string
  default     = "eastus2"
}

# Build inside an existing resource group instead of a throwaway pkr-* one.
#
# Left null, Packer creates a pkr-Resource-Group-* per build, which needs
# resourceGroups/write at SUBSCRIPTION scope. The CI service principal holds
# Contributor on named resource groups only, so CI always passes this
# (vars.GALLERY_RESOURCE_GROUP, where the intermediate managed image lands too).
# Null still works for a local build by someone with subscription rights.
#
# A dead build now leaks loose pkrvm/pkrni/pkros resources into this group
# instead of a whole pkr-* group; packer-cleanup.sh sweep-build-resources
# handles that shape.
variable "build_resource_group_name" {
  description = "Existing resource group to build in. Null = let Packer create a temporary pkr-* group (needs subscription-scope rights)."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "VM size for the build VM"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 64
}

# Build VM networking (optional - uses default if not specified)
variable "build_vnet_name" {
  description = "VNet name for build VM (optional)"
  type        = string
  default     = null
}

variable "build_subnet_name" {
  description = "Subnet name for build VM (optional)"
  type        = string
  default     = null
}

variable "build_vnet_resource_group_name" {
  description = "Resource group for build VNet (optional)"
  type        = string
  default     = null
}

# Application configuration
variable "php_version" {
  description = "PHP version to install"
  type        = string
  default     = "8.3"
}

# lib-main integration
variable "drupal_repo" {
  description = "Git repository URL for Drupal codebase (e.g., https://github.com/utkdigitalinitiatives/lib-main.git)"
  type        = string
  default     = ""
}

variable "drupal_ref" {
  description = "Git ref (branch, tag, or SHA) to checkout"
  type        = string
  default     = "main"
}
