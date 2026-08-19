# lib-main-infra

Infrastructure as Code for the lib-main Drupal application.

## Architecture

This repository contains the Azure infrastructure for running a Drupal 11 application:

- **Azure Load Balancer** → **VMSS** (Rocky Linux 9) → **PostgreSQL Flexible Server**
- **Azure Blob Storage** for public Drupal media (via the `az_blob_fs` Drupal module — native Azure Blob PHP SDK)
- **Azure Files** (SMB share on a dedicated storage account) mounted at `/var/www/drupal/private` for Drupal's `private://` filesystem, so editor-only uploads survive VMSS reimages
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
│   ├── production-schedule.yml     # Weekday start/stop of production VMSS + PSQL
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

The current production environment was bootstrapped once in early 2026 and is not torn down. The steps below are for setting up a *new* deployment from scratch.

`bootstrap/azure-setup.sh` is preserved as a historical reference for the original deploy but has drifted from current architecture (Key Vault, marketplace terms, deprecated CLI flags). **Audit it against this README and the header in the script before running.** Plan on hand-running the equivalent steps rather than executing it blindly.

1. **Foundational Azure resources** — resource groups (`lib-main-images-rg`, `lib-main-tfstate-rg`), the Compute Gallery (`lib_main_gallery`) with `drupal-base-rocky-linux-9` and `drupal-rocky-linux-9` image definitions, the Terraform state storage account + `tfstate` container, and the `lib-main-github-actions` service principal. See `bootstrap/azure-setup.sh` for the original commands.

2. **Accept Rocky Linux marketplace terms** — apply `bootstrap/marketplace-agreement/`. Required before Packer can build the base image.

3. **Apply `environments/secrets/`** — provisions `lib-main-secrets-rg` and the shared Key Vault. Needs the GitHub Actions SP's *object ID* (`az ad sp show --id <appId> --query id -o tsv`) for the role assignment.

4. **Seed manual Key Vault secrets** — `production-db-admin-password`, `devtest-db-admin-password`, `shared-postmark-api-token`. The TF-managed secrets (Drupal admin password, hash salts, storage keys) populate themselves on subsequent applies.

5. **Apply `environments/devtest/`, then `environments/production/` and `environments/dev/`** — dev reads `devtest-storage-account-key` from the vault, so devtest must apply first.

6. **Configure GitHub secrets**:
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `SSH_PUBLIC_KEY`

   Application secrets (DB passwords, hash salts, storage keys, Postmark token) live in the Key Vault — see [Key Vault](#key-vault) — not in GitHub secrets. Workflows fetch them via `az keyvault secret show` after `azure/login`.

7. **Configure GitHub variables**:
   - `GALLERY_NAME`: `lib_main_gallery`
   - `GALLERY_RESOURCE_GROUP`: `lib-main-images-rg`
   - `LOCATION`: `eastus2`
   - `TF_STATE_RESOURCE_GROUP`: `lib-main-tfstate-rg`
   - `TF_STATE_STORAGE_ACCOUNT`: (from step 1)
   - `SUBNET_ID`: (from production Terraform output)
   - `LB_DNS_LABEL`: `lib-main` (or preferred DNS label)
   - `DEVTEST_DB_HOST`: (from devtest Terraform output)
   - `DEVTEST_STORAGE_ACCOUNT`: (from devtest Terraform output)
   - `DRUPAL_SITE_UUID`: Fixed Drupal site UUID for config sync (`uuidgen`)
   - `DOMAIN_NAME`: Public domain for the application (e.g., `libdev1.lib.utk.edu`)
   - `PUBLIC_IP_ID`: Resource ID of the external public IP attached to the load balancer

8. **Build base image** — run `base-image-build.yml` manually before any dispatch-driven workflow.

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `base-image-build.yml` | Monthly / Manual / Base file changes | Build base image with system packages |
| `build-on-dispatch.yml` | `drupal-dev-merge` dispatch from lib-main | Build image → sync DB → deploy dev VM |
| `deploy-on-main-merge.yml` | `drupal-main-merge` dispatch / Manual | Production deploy → dev VM cleanup |
| `deploy-production.yml` | Manual | Rolling update to production (rollback/emergency) |
| `production-schedule.yml` | Weekday cron / Manual | Start production VMSS + PostgreSQL at 6:30 AM ET, deallocate them at 5:30 PM ET |
| `test-cloud-init.yml` | Manual | Test cloud-init changes on dev VMs |

Production is deliberately **not** running overnight or on weekends — `production-schedule.yml` deallocates the VMSS and stops the PostgreSQL server outside weekday business hours. Start them early with the workflow's manual `start` action if you need the site up off-hours (a deploy triggered while production is stopped updates the scale set model but leaves the instance deallocated).

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
2. **Deploy to Production** — Rolling update to the production VMSS. MaxSurge is enabled, so the upgrade brings up a replacement instance and waits for it to report healthy before deleting the old one (steady state stays at one instance)
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

## Production VNet addressing

`drupal-production-vnet` is `10.20.0.0/16` (web subnet `10.20.1.0/24`, private
endpoints subnet `10.20.2.0/24`), the range reserved for lib-main in the
[mccarthy-infra](https://github.com/utkdigitalinitiatives/mccarthy-infra#vnet-address-allocation)
allocation table.

Do not move it back into `10.0.0.0/16`: that range is the Kubernetes **service
CIDR** of the Asimov AKS cluster, which this VNet is to peer with for SolrCloud.
Azure validates only VNet address spaces when peering, so an overlap with the
service CIDR appears to work — but ClusterIPs are allocated from that range, and
reply traffic to a VM inside it can be intercepted by kube-proxy on the cluster
nodes. Microsoft documents service-CIDR overlap with a peered network as
unsupported, and `serviceCidr` is immutable after cluster creation. `10.1.0.0/16`
is also off-limits: the already-peered `vireo-db` spoke partly occupies it.

Azure applies address-space changes in place, but only against empty subnets:
the VMSS must be scaled to 0 first, and the move needs a transitional apply
carrying both address spaces before the old one can be dropped. Consult the
allocation table before any change.

## Key Vault

Application secrets are stored in `lib-main-kv-4ad11abb` (in `lib-main-secrets-rg`), provisioned by `environments/secrets/`. RBAC mode, purge protection enabled, 90-day soft delete.

| Secret | Used by |
|--------|---------|
| `production-db-admin-password` | Production PSQL + VMSS cloud-init + DB sync workflows |
| `devtest-db-admin-password` | DevTest PSQL + dev VM cloud-init + DB sync workflows |
| `production-drupal-admin-password` | Mirror of Terraform-managed Drupal admin password |
| `production-drupal-hash-salt` | Production VMSS cloud-init |
| `dev-drupal-hash-salt` | Dev VM cloud-init |
| `production-storage-account-key` | Production VMSS cloud-init (media blob access) |
| `production-private-files-storage-key` | Production VMSS cloud-init (SMB mount of the `private://` share) |
| `devtest-storage-account-key` | Dev VM cloud-init + dev env data source |
| `shared-postmark-api-token` | Email notification workflows |
| `migrate-pantheon-db` | Optional. JSON credentials for the legacy Pantheon source DB, consumed by `drush migrate:*`. Cloud-init injects it only if present; absent is the normal state outside a migration run |

VMSS and dev VM managed identities have `Key Vault Secrets User`; cloud-init fetches secrets via IMDS at boot and substitutes them into `/etc/drupal/environment.php`. GitHub Actions SP and operators have `Key Vault Secrets Officer`.

**Apply order**: `secrets` → `devtest` → `production` / `dev` (dev reads `devtest-storage-account-key`, so devtest must apply first).

## License

Public repository - UTK Libraries
