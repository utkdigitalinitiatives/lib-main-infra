# Base Image for Drupal - Rocky Linux 9
# This image contains all system-level dependencies and is rebuilt monthly.
# The app image (drupal-rocky9.pkr.hcl) builds on top of this for Drupal-specific tasks.
# Plugin requirements are in plugins.pkr.hcl

# Source: Azure ARM builder
source "azure-arm" "drupal-base" {
  # Authentication
  use_azure_cli_auth = var.use_azure_cli_auth
  subscription_id    = var.subscription_id
  client_id          = var.client_id
  client_secret      = var.client_secret
  tenant_id          = var.tenant_id

  # Build VM configuration
  location = var.location
  vm_size  = var.vm_size

  # Base image: Rocky Linux 9 from marketplace
  image_publisher = "resf"
  image_offer     = "rockylinux-x86_64"
  image_sku       = "9-base"

  # Required for Rocky Linux marketplace image
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
    image_name           = var.base_image_name
    image_version        = var.image_version
    replication_regions  = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  # Managed image configuration (intermediate)
  managed_image_resource_group_name = var.gallery_resource_group_name
  managed_image_name                = "drupal-base-rocky9-${var.image_version}"

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
    Application = "drupal-base"
    Builder     = "packer"
    Version     = var.image_version
    OS          = "rocky-linux-9"
    ImageType   = "base"
    BuildDate   = timestamp()
  }
}

# Build configuration
build {
  name    = "drupal-base-rocky9"
  sources = ["source.azure-arm.drupal-base"]

  # Provisioner: Ansible for base system configuration
  provisioner "ansible" {
    playbook_file = "${path.root}/ansible/playbook-base.yml"
    user          = "packer"

    extra_arguments = [
      "--extra-vars", "ansible_become=true",
      "--extra-vars", "php_version=${var.php_version}"
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
