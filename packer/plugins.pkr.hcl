# Shared Packer plugin requirements
# This file is shared by both drupal-rocky9.pkr.hcl and drupal-base-rocky9.pkr.hcl

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}
