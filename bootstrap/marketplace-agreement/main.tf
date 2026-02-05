# ------------------------------------------------------------------------------
# Marketplace Agreement
# ------------------------------------------------------------------------------
# Accepts the Azure Marketplace terms for Rocky Linux 9.
# This must be run once per subscription before Packer can build images.
#
# Usage:
#   cd bootstrap/marketplace-agreement
#   terraform init
#   terraform apply
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# Accept Rocky Linux 9 marketplace terms
resource "azurerm_marketplace_agreement" "rockylinux" {
  publisher = "resf"
  offer     = "rockylinux-x86_64"
  plan      = "9-base"
}

output "agreement_accepted" {
  description = "Confirmation that marketplace agreement was accepted"
  value       = "Rocky Linux 9 (resf/rockylinux-x86_64/9-base) marketplace terms accepted"
}
