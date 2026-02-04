# Drupal App Image - Rocky Linux 9
# This image builds on top of the base image and adds Drupal-specific components.
# The base image (drupal-base-rocky9.pkr.hcl) provides system dependencies.
# Plugin requirements are in plugins.pkr.hcl
#
# Two-tier build strategy: Base image (~27 min monthly) + App image (~21 min per PR)
#
# lib-main integration: When drupal_repo is provided, clones from Git instead of
# using composer create-project. This allows the Drupal codebase to be maintained
# in a separate repository.

# Source: Azure ARM builder using base image from gallery
source "azure-arm" "drupal" {
  # Authentication
  use_azure_cli_auth = var.use_azure_cli_auth
  subscription_id    = var.subscription_id
  client_id          = var.client_id
  client_secret      = var.client_secret
  tenant_id          = var.tenant_id

  # Build VM configuration
  location = var.location
  vm_size  = var.vm_size

  # Source image: Base image from Shared Image Gallery
  # This replaces the marketplace image for faster builds
  shared_image_gallery {
    subscription   = var.subscription_id
    resource_group = var.gallery_resource_group_name
    gallery_name   = var.gallery_name
    image_name     = var.base_image_name
    image_version  = var.base_image_version
  }

  # Required: Plan info from the original marketplace image (Rocky Linux)
  # Azure requires this even when using a gallery image derived from marketplace
  plan_info {
    plan_name      = "9-base"
    plan_product   = "rockylinux-x86_64"
    plan_publisher = "resf"
  }

  # Output to Shared Image Gallery
  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.gallery_resource_group_name
    gallery_name         = var.gallery_name
    image_name           = var.image_name
    image_version        = var.image_version
    replication_regions  = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  # Managed image configuration (intermediate)
  managed_image_resource_group_name = var.gallery_resource_group_name
  managed_image_name                = "drupal-rocky9-${var.image_version}"

  # OS disk configuration
  os_type         = "Linux"
  os_disk_size_gb = var.os_disk_size_gb

  # Build VM networking
  virtual_network_name                = var.build_vnet_name
  virtual_network_subnet_name         = var.build_subnet_name
  virtual_network_resource_group_name = var.build_vnet_resource_group_name

  # SSH configuration
  communicator = "ssh"
  ssh_username = "packer"

  # Azure tags for the build VM and resulting image
  azure_tags = {
    Application    = "drupal"
    Builder        = "packer"
    Version        = var.image_version
    OS             = "rocky-linux-9"
    ImageType      = "app"
    BaseImageVer   = var.base_image_version
    DrupalRepo     = var.drupal_repo != "" ? var.drupal_repo : "composer-create-project"
    DrupalRef      = var.drupal_ref
    BuildDate      = timestamp()
  }
}

# Build configuration
build {
  name    = "drupal-rocky9"
  sources = ["source.azure-arm.drupal"]

  # Provisioner: Ansible (using piped transfer to avoid SFTP dependency)
  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/playbook.yml"
    user          = "packer"

    extra_arguments = [
      "--extra-vars", "ansible_become=true",
      "--extra-vars", "php_version=${var.php_version}",
      "--extra-vars", "drupal_env=production",
      "--extra-vars", "drupal_repo=${var.drupal_repo}",
      "--extra-vars", "drupal_ref=${var.drupal_ref}"
    ]

    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_ARGS=-o ControlMaster=auto -o ControlPersist=60s",
      "ANSIBLE_SSH_TRANSFER_METHOD=piped"
    ]
  }

  # Provisioner: Cleanup and generalize for Azure
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      # Clean package cache
      "dnf clean all",
      "rm -rf /var/cache/dnf/*",

      # Remove temporary files
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",

      # Remove SSH host keys (regenerated on first boot)
      "rm -f /etc/ssh/ssh_host_*",

      # Clear logs
      "truncate -s 0 /var/log/*.log 2>/dev/null || true",
      "truncate -s 0 /var/log/**/*.log 2>/dev/null || true",
      "journalctl --vacuum-time=1s || true",

      # Clear machine-id (regenerated on first boot)
      "truncate -s 0 /etc/machine-id",

      # Clear bash history
      "rm -f /root/.bash_history",
      "rm -f /home/*/.bash_history 2>/dev/null || true",

      # Deprovision Azure agent
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}
