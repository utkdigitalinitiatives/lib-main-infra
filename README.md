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
│   ├── base-image-build.yml        # Monthly base image build
│   ├── build-on-dispatch.yml       # Dev merge: build image → dev VM
│   ├── deploy-on-main-merge.yml    # Main merge: production deploy → dev cleanup
│   ├── deploy-production.yml       # Manual production rolling update
├── packer/
│   ├── drupal-base-rocky9.pkr.hcl  # Base image (system packages)
│   ├── drupal-rocky9.pkr.hcl       # App image (Drupal code)
│   └── ansible/                     # Ansible playbooks
├── modules/                         # Reusable Terraform modules
├── environments/
│   ├── production/                  # Production environment
│   ├── devtest/                     # Permanent shared PostgreSQL + Automation
│   └── dev/                         # Shared dev validation
└── bootstrap/                       # Azure setup scripts
```

### Integration with lib-main

This infrastructure repo works with the [lib-main](https://github.com/utkdigitalinitiatives/lib-main) Drupal codebase:

1. Developers create feature branches, open PRs to the `dev` branch
2. When a PR is merged to `dev`, lib-main sends a `drupal-dev-merge` dispatch to this repo
3. This repo builds a Packer image and deploys a dev VM for validation
4. When `dev` is merged to `main`, lib-main sends a `drupal-main-merge` dispatch
5. This repo deploys the latest image to production and cleans up the dev VM

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
   - `DEVTEST_DB_HOST`: (created after devtest Terraform apply)
   - `DRUPAL_SITE_UUID`: Fixed Drupal site UUID for config sync

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
| `build-on-dispatch.yml` | `drupal-dev-merge` dispatch from lib-main | Build image → sync DB → deploy dev VM → dev-review |
| `deploy-on-main-merge.yml` | `drupal-main-merge` dispatch / Manual | Production deploy → dev VM cleanup |
| `deploy-production.yml` | Manual | Rolling update to production (rollback/emergency) |
| `test-cloud-init.yml` | Manual | Test cloud-init changes on dev VMs |

### Dev → Production Pipeline

When code is merged to the `dev` branch in [lib-main](https://github.com/utkdigitalinitiatives/lib-main):

```
build-image → prepare-database → deploy-dev → dev-review
```

1. **Build Image** — Packer builds a new image (version `0.0.{RUN_NUMBER}`)
2. **Prepare Database** — Production database is synced to the devtest PostgreSQL instance
3. **Deploy Dev** — Shared dev VM deployed with the new image for validation
4. **Dev Review** — Manual approval gate

When `dev` is merged to `main`:

```
get-image-version → deploy-production (approval gate) → cleanup-dev
```

1. **Get Image Version** — Queries gallery for latest image
2. **Deploy to Production** — Rolling update to the production VMSS (requires approval)
3. **Cleanup Dev** — Destroys the shared dev VM and resources

## Azure Resources

| Resource Group | Purpose |
|----------------|---------|
| `lib-main-images-rg` | Azure Compute Gallery and Packer resources |
| `lib-main-tfstate-rg` | Terraform state storage |
| `lib-main-production-rg` | Production infrastructure |
| `lib-main-devtest-rg` | Permanent shared PostgreSQL + Automation |
| `lib-main-dev-rg` | Shared dev validation resources |

## License

Public repository - UTK Libraries
