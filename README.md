# lib-main-infra

Infrastructure as Code for the lib-main Drupal application.

## Architecture

This repository contains the Azure infrastructure for running a Drupal 11 application:

- **Azure Load Balancer** → **VMSS** (Rocky Linux 9) → **PostgreSQL Flexible Server**
- **Azure Blob Storage** for Drupal media (via the `az_blob_fs` Drupal module — native Azure Blob PHP SDK)
- **Azure Key Vault** for shared secrets (DB passwords, hash salts, storage keys, Postmark token)
- **Azure Compute Gallery** for Packer-built images

### Repository Structure

```
lib-main-infra/
├── .github/workflows/
│   ├── base-image-build.yml        # Monthly base image build
│   ├── build-on-dispatch.yml       # Dev merge: build image → dev VM
│   ├── deploy-on-main-merge.yml    # Main merge: production deploy → dev cleanup
│   ├── deploy-production.yml       # Manual production rolling update
│   └── test-cloud-init.yml         # Manual cloud-init testing on dev VMs
├── packer/
│   ├── plugins.pkr.hcl             # Shared plugin requirements
│   ├── variables.pkr.hcl           # Shared variables
│   ├── drupal-base-rocky9.pkr.hcl  # Base image (system packages)
│   ├── drupal-rocky9.pkr.hcl       # App image (Drupal code)
│   └── ansible/
│       ├── playbook-base.yml       # Base provisioning
│       ├── playbook.yml            # App provisioning
│       └── templates/              # Jinja2 templates (Apache, PHP-FPM)
├── modules/                         # Reusable Terraform modules
├── environments/
│   ├── secrets/                     # Shared Key Vault (apply first)
│   ├── production/                  # Production environment
│   ├── devtest/                     # Permanent shared PostgreSQL + Automation
│   └── dev/                         # Shared dev validation
└── bootstrap/                       # Azure setup scripts
```

### Integration with lib-main

This infrastructure repo works with the [lib-main](https://github.com/utkdigitalinitiatives/lib-main) Drupal codebase:

1. On push to `dev` in lib-main, a `drupal-dev-merge` dispatch is sent to this repo
2. This repo builds a Packer image and deploys the shared dev VM for validation
3. On push to `main` in lib-main, a `drupal-main-merge` dispatch is sent to this repo
4. This repo deploys the latest image to production and cleans up the dev VM

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

   Application secrets (DB passwords, hash salts, storage keys, Postmark token) live in the shared Key Vault — see [Key Vault](#key-vault) — not in GitHub secrets. Workflows fetch them via `az keyvault secret show` after `azure/login`.

3. **Configure GitHub variables**:
   - `GALLERY_NAME`: `lib_main_gallery`
   - `GALLERY_RESOURCE_GROUP`: `lib-main-images-rg`
   - `LOCATION`: `eastus2`
   - `TF_STATE_RESOURCE_GROUP`: `lib-main-tfstate-rg`
   - `TF_STATE_STORAGE_ACCOUNT`: (from bootstrap output)
   - `SUBNET_ID`: (created after first Terraform apply)
   - `LB_DNS_LABEL`: `lib-main` (or preferred DNS label)
   - `DEVTEST_DB_HOST`: (created after devtest Terraform apply)
   - `DEVTEST_STORAGE_ACCOUNT`: (created after devtest Terraform apply)
   - `DRUPAL_SITE_UUID`: Fixed Drupal site UUID for config sync
   - `DOMAIN_NAME`: Public domain for the application (e.g., `libdev1.lib.utk.edu`)
   - `PUBLIC_IP_ID`: Resource ID of the external public IP attached to the load balancer

4. **Build base image first**:
   Run `base-image-build.yml` workflow manually before any PR workflow.

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `base-image-build.yml` | Monthly / Manual / Base file changes | Build base image with system packages |
| `build-on-dispatch.yml` | `drupal-dev-merge` dispatch from lib-main | Build image → sync DB → deploy dev VM |
| `deploy-on-main-merge.yml` | `drupal-main-merge` dispatch / Manual | Production deploy → dev VM cleanup |
| `deploy-production.yml` | Manual | Rolling update to production (rollback/emergency) |
| `test-cloud-init.yml` | Manual | Test cloud-init changes on dev VMs |

### Dev → Production Pipeline

When code is merged to the `dev` branch in [lib-main](https://github.com/utkdigitalinitiatives/lib-main):

```
build-image → prepare-database → deploy-dev
```

1. **Build Image** — Packer builds a new image (version `0.0.{RUN_NUMBER}`)
2. **Prepare Database** — Production database is synced to the devtest PostgreSQL instance
3. **Deploy Dev** — Shared dev VM deployed with the new image for validation

When `dev` is merged to `main`:

```
get-image-version → deploy-production → cleanup-dev
```

1. **Get Image Version** — Queries gallery for latest image
2. **Deploy to Production** — Rolling update to the production VMSS
3. **Cleanup Dev** — Destroys the shared dev VM and resources

## Azure Resources

| Resource Group | Purpose |
|----------------|---------|
| `lib-main-images-rg` | Azure Compute Gallery and Packer resources |
| `lib-main-tfstate-rg` | Terraform state storage |
| `lib-main-secrets-rg` | Shared Key Vault (`lib-main-kv-4ad11abb`) |
| `lib-main-production-rg` | Production infrastructure |
| `lib-main-devtest-rg` | Permanent shared PostgreSQL + Automation |
| `lib-main-dev-rg` | Shared dev validation resources |

## Key Vault

Application secrets are stored in `lib-main-kv-4ad11abb` (in `lib-main-secrets-rg`), provisioned by `environments/secrets/`. RBAC mode, purge protection enabled, 90-day soft delete.

| Secret | Used by |
|--------|---------|
| `production-db-admin-password` | Production PSQL + VMSS cloud-init + DB sync workflows |
| `devtest-db-admin-password` | DevTest PSQL + dev VM cloud-init + DB sync workflows |
| `production-drupal-admin-password` | Mirror of Terraform-managed Drupal admin password |
| `production-drupal-hash-salt` | Production VMSS cloud-init |
| `dev-drupal-hash-salt` | Dev VM cloud-init |
| `production-storage-account-key` | Production VMSS cloud-init (blob access) |
| `devtest-storage-account-key` | Dev VM cloud-init + dev env data source |
| `shared-postmark-api-token` | Email notification workflows |

VMSS and dev VM managed identities have `Key Vault Secrets User`; cloud-init fetches secrets via IMDS at boot and substitutes them into `/etc/drupal/environment.php`. GitHub Actions SP and operators have `Key Vault Secrets Officer`.

**Apply order**: `secrets` → `devtest` → `production` / `dev` (dev reads `devtest-storage-account-key`, so devtest must apply first).

## License

Public repository - UTK Libraries
