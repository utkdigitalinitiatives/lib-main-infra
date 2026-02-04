# lib-main-infra

Infrastructure as Code for the lib-main Drupal application.

## Architecture

This repository contains the Azure infrastructure for running a Drupal 11 application:

- **Azure Load Balancer** → **VMSS** (Rocky Linux 9) → **PostgreSQL Flexible Server**
- **Azure Blob Storage** (via S3Proxy for S3FS module compatibility)
- **Azure Compute Gallery** for Packer-built images

### Repository Structure

```
lib-main-infra/
├── .github/workflows/
│   ├── base-image-build.yml    # Monthly base image build
│   ├── build-on-dispatch.yml   # Triggered by lib-main repo
│   ├── deploy-production.yml   # Production rolling update
│   └── cleanup-pr.yml          # PR resource cleanup
├── packer/
│   ├── drupal-base-rocky9.pkr.hcl  # Base image (system packages)
│   ├── drupal-rocky9.pkr.hcl       # App image (Drupal code)
│   └── ansible/                     # Ansible playbooks
├── modules/                         # Reusable Terraform modules
├── environments/
│   ├── production/                  # Production environment
│   ├── dev/                         # Ephemeral PR dev stage
│   └── test/                        # Ephemeral PR test stage
└── bootstrap/                       # Azure setup scripts
```

### Integration with lib-main

This infrastructure repo works with the [lib-main](https://github.com/utkdigitalinitiatives/lib-main) Drupal codebase:

1. Developers push code to lib-main
2. lib-main's workflow sends `repository_dispatch` to this repo
3. This repo builds a Packer image with the lib-main code
4. The image is deployed through dev → test → production

## Quick Start

### Prerequisites

- Azure CLI installed and logged in
- Terraform >= 1.0
- Packer (for local builds)
- Access to UTK-Library-Systems Azure subscription

### Initial Setup

1. **Bootstrap Azure resources** (one-time):
   ```bash
   cd bootstrap
   chmod +x azure-setup.sh
   ./azure-setup.sh
   ```

2. **Configure GitHub secrets** (see output from bootstrap script):
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `SSH_PUBLIC_KEY`
   - `DB_ADMIN_PASSWORD`

3. **Configure GitHub variables**:
   - `GALLERY_NAME`: `lib_main_gallery`
   - `GALLERY_RESOURCE_GROUP`: `lib-main-images-rg`
   - `LOCATION`: `eastus2`
   - `TF_STATE_RESOURCE_GROUP`: `lib-main-tfstate-rg`
   - `TF_STATE_STORAGE_ACCOUNT`: (from bootstrap output)
   - `SUBNET_ID`: (created after first Terraform apply)
   - `LB_DNS_LABEL`: `lib-main` (or preferred DNS label)

4. **Build base image first**:
   Run `base-image-build.yml` workflow manually before any PR workflow.

### Local Development

```bash
# Initialize Terraform
cd environments/production
terraform init -backend=false

# Validate configuration
terraform validate

# Plan changes (with backend disabled)
terraform plan -var="subscription_id=..." -var="admin_ssh_public_key=..." ...
```

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `base-image-build.yml` | Monthly / Manual / Base file changes | Build base image with system packages |
| `build-on-dispatch.yml` | `repository_dispatch` from lib-main | Build app image + run PR workflow |
| `deploy-production.yml` | Manual | Rolling update to production |
| `cleanup-pr.yml` | PR closed / `drupal-pr-closed` dispatch | Destroy ephemeral resources |

## Azure Resources

| Resource Group | Purpose |
|----------------|---------|
| `lib-main-images-rg` | Azure Compute Gallery and Packer resources |
| `lib-main-tfstate-rg` | Terraform state storage |
| `lib-main-production-rg` | Production infrastructure |
| `lib-main-dev-pr-{N}-rg` | Ephemeral PR resources |

## License

Private repository - UTK Libraries
