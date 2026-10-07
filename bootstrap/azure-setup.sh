#!/usr/bin/env bash
# ==============================================================================
# Azure bootstrap for lib-main-infra
# ==============================================================================
# Creates or repairs everything Terraform cannot do for itself: the resource
# groups, the shared gallery, Terraform state storage, and the GitHub Actions
# service principal with its federated credentials and role assignments.
#
# Idempotent: every step checks for an existing resource first. Re-running it is
# the supported way to repair lib-main-github-actions if a role assignment or
# federated credential goes missing - nothing else will recreate them.
#
# What this creates:
#   - Six resource groups (images, tfstate, secrets, production, devtest, dev).
#     Terraform READS these and never creates or deletes them; see below.
#   - lib_main_gallery and its two image definitions. The gallery is SHARED:
#     sibling repos (mccarthy-infra) publish into it and build on its base image.
#   - The Terraform state storage account + tfstate container
#   - The lib-main-github-actions app registration + service principal, with
#     federated (OIDC) credentials and NO password
#   - Role assignments scoped to named resource groups and resources
#
# Why no subscription-scope role. The SP used to hold Contributor on the whole
# subscription, granted once by hand and held nowhere in code. Subscription-level
# RBAC belongs to OIT's governance (grp-sub-*-{owners,contributors,...} groups),
# so a direct SP assignment there is exactly what a restructure can sweep - and
# it is the identity that runs Terraform, so losing it locks CI out with nothing
# able to self-heal. Every grant below is resource-group or resource scoped,
# which OIT has confirmed it does not touch.
#
# That scoping is why resource groups live here: Contributor on a named group
# cannot create a new group, and deleting a group deletes the SP's assignment on
# it. Same reason Packer builds inside lib-main-images-rg instead of a throwaway
# pkr-* group (build_resource_group_name).
#
# What this deliberately does NOT do:
#   - Accept Rocky Linux marketplace terms - apply bootstrap/marketplace-agreement/.
#   - Grant Key Vault Secrets Officer - environments/secrets/ owns that one.
#   - Remove the legacy subscription Contributor or the legacy client secret.
#     It reports both and prints the commands; remove them only after CI has
#     run green on OIDC + scoped roles (see the summary at the end).
#   - Seed Key Vault secrets (production-db-admin-password,
#     devtest-db-admin-password, shared-postmark-api-token).
#
# Prerequisites: az CLI logged in (activate PIM first - without it `az ... list`
# returns empty instead of erroring) with rights to assign roles at resource
# group scope, and owner of the app registration; gh CLI logged in.
#
# Deploy order from nothing:
#   1. This script
#   2. bootstrap/marketplace-agreement/ (Rocky Linux terms)
#   3. environments/secrets/, then seed the three manual Key Vault secrets
#   4. environments/devtest/
#   5. environments/production/, then environments/dev/ (CI-owned)
#   6. base-image-build.yml
#
# Usage:
#   ./bootstrap/azure-setup.sh
# ==============================================================================

set -euo pipefail

# --- Configuration ------------------------------------------------------------

# By GUID, never by display name. OIT renames the subscription
# (UTK-Library-Systems -> sub-utk-library-systems-prod); the GUID does not change.
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-9fc717ef-b8c4-4858-a677-7c7b518616a0}"
LOCATION="${LOCATION:-eastus2}"

GITHUB_ORG="${GITHUB_ORG:-utkdigitalinitiatives}"
INFRA_REPO="${INFRA_REPO:-lib-main-infra}"
SP_NAME="${SP_NAME:-lib-main-github-actions}"

IMAGES_RG="lib-main-images-rg"
TFSTATE_RG="lib-main-tfstate-rg"
SECRETS_RG="lib-main-secrets-rg"
PRODUCTION_RG="lib-main-production-rg"
DEVTEST_RG="lib-main-devtest-rg"
DEV_RG="lib-main-dev-rg"
ALL_RGS=("$IMAGES_RG" "$TFSTATE_RG" "$SECRETS_RG" "$PRODUCTION_RG" "$DEVTEST_RG" "$DEV_RG")

GALLERY_NAME="lib_main_gallery"
BASE_IMAGE_DEF="drupal-base-rocky-linux-9"
APP_IMAGE_DEF="drupal-rocky-linux-9"

# Sibling sites' groups that run VMs booted from lib_main_gallery images.
# gallery-prune.py keeps every version a live VM or VMSS runs, but the SP can only
# see VMs where it holds a role - `az vmss list` silently omits the rest. Without
# Reader here, a sibling's running production image looks unused. Add a new
# site's production and dev groups when it first deploys.
CONSUMER_RESOURCE_GROUPS="${CONSUMER_RESOURCE_GROUPS:-mccarthy-production-rg mccarthy-dev-rg}"

# The production load balancer fronts an externally managed public IP in
# dns-test-rg. Any PUT on the LB re-checks join rights on that IP, so without a
# grant there every LB change in CI fails with LinkedAuthorizationFailed.
PUBLIC_IP_ID="${PUBLIC_IP_ID:-$(gh variable get PUBLIC_IP_ID --repo "$GITHUB_ORG/$INFRA_REPO" 2>/dev/null || true)}"

banner() { printf '\n=== %s ===\n' "$1"; }

# --- Subscription -------------------------------------------------------------

banner "Subscription"
az account set --subscription "$SUBSCRIPTION_ID"
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo "Tenant:       $TENANT_ID"

# --- Resource groups ----------------------------------------------------------

banner "Resource groups"
for rg in "${ALL_RGS[@]}"; do
  if az group show --name "$rg" >/dev/null 2>&1; then
    echo "exists:  $rg"
  else
    az group create --name "$rg" --location "$LOCATION" --output none
    echo "created: $rg"
  fi
done

# --- Shared image gallery -----------------------------------------------------

banner "Image gallery"
if az sig show --resource-group "$IMAGES_RG" --gallery-name "$GALLERY_NAME" >/dev/null 2>&1; then
  echo "exists:  $GALLERY_NAME"
else
  az sig create --resource-group "$IMAGES_RG" --gallery-name "$GALLERY_NAME" \
    --location "$LOCATION" --output none
  echo "created: $GALLERY_NAME"
fi

ensure_image_definition() {
  local def="$1" offer="$2"
  if az sig image-definition show --resource-group "$IMAGES_RG" --gallery-name "$GALLERY_NAME" \
      --gallery-image-definition "$def" >/dev/null 2>&1; then
    echo "exists:  $def"
  else
    az sig image-definition create \
      --resource-group "$IMAGES_RG" \
      --gallery-name "$GALLERY_NAME" \
      --gallery-image-definition "$def" \
      --publisher UTKLibraries \
      --offer "$offer" \
      --sku rocky-linux-9 \
      --os-type Linux \
      --os-state Generalized \
      --hyper-v-generation V2 \
      --output none
    echo "created: $def"
  fi
}
ensure_image_definition "$BASE_IMAGE_DEF" drupal-base
ensure_image_definition "$APP_IMAGE_DEF" drupal

# --- Terraform state storage --------------------------------------------------

banner "Terraform state storage"
STORAGE_NAME=$(az storage account list --resource-group "$TFSTATE_RG" \
  --query "[?starts_with(name, 'libmaintfstate')].name | [0]" -o tsv 2>/dev/null || true)

if [ -n "$STORAGE_NAME" ] && [ "$STORAGE_NAME" != "null" ]; then
  echo "exists:  $STORAGE_NAME"
else
  STORAGE_NAME="libmaintfstate$(openssl rand -hex 4)"
  az storage account create \
    --name "$STORAGE_NAME" \
    --resource-group "$TFSTATE_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
  echo "created: $STORAGE_NAME"
fi

# Key auth for the container check: a brand-new account has no data-plane role
# assignments yet, and the operator's Owner role does not confer one.
if az storage container show --name tfstate --account-name "$STORAGE_NAME" --auth-mode key >/dev/null 2>&1; then
  echo "exists:  container tfstate"
else
  az storage container create --name tfstate --account-name "$STORAGE_NAME" --auth-mode key --output none
  echo "created: container tfstate"
fi

STORAGE_ID=$(az storage account show --name "$STORAGE_NAME" --resource-group "$TFSTATE_RG" --query id -o tsv)

# --- Service principal with federated (OIDC) credentials -----------------------
#
# Workflows present a short-lived GitHub OIDC token and Entra exchanges it for an
# access token. No AZURE_CLIENT_SECRET to store, rotate, expire, or leak.

banner "Service principal (OIDC)"
APP_ID=$(az ad app list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
  echo "exists:  app registration $SP_NAME ($APP_ID)"
else
  APP_ID=$(az ad app create --display-name "$SP_NAME" --query appId -o tsv)
  echo "created: app registration $SP_NAME ($APP_ID)"
fi

if az ad sp show --id "$APP_ID" >/dev/null 2>&1; then
  echo "exists:  service principal"
else
  az ad sp create --id "$APP_ID" --output none
  echo "created: service principal"
fi

SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "SP object ID: $SP_OBJECT_ID"

# Subjects must match exactly what GitHub presents - Entra does no wildcarding.
#   - repository_dispatch, schedule, and push events run on the default branch,
#     and so does workflow_dispatch when started from main: ref:refs/heads/main.
#   - A job that declares `environment:` presents environment:<name> instead,
#     on ANY branch. deploy-dev (build-on-dispatch.yml) and test-cloud-init.yml
#     use dev; deploy-production.yml uses production.
#   - Anything else started from a non-main branch has no credential and fails
#     azure/login with AADSTS700213 naming the subject it presented.
#
# Ask GitHub for the prefix instead of composing it. Newer repos get an immutable
# form with numeric IDs (mccarthy-infra does); lib-main-infra still gets
# repo:<org>/<repo> today, and a repo rename would change that.
SUB_PREFIX=$(gh api "repos/${GITHUB_ORG}/${INFRA_REPO}/actions/oidc/customization/sub" \
  --jq '.sub_claim_prefix // empty' 2>/dev/null || true)
if [ -z "$SUB_PREFIX" ]; then
  SUB_PREFIX="repo:${GITHUB_ORG}/${INFRA_REPO}"
  echo "warn:    could not read the OIDC subject prefix from GitHub; assuming $SUB_PREFIX"
else
  echo "OIDC subject prefix: $SUB_PREFIX"
fi

add_federated_credential() {
  local name="$1" subject="$2" current
  # Match on name but reconcile on subject. A stale subject fails every run, and
  # the claim format changing under a working deployment is exactly when someone
  # re-runs this script.
  current=$(az ad app federated-credential show \
    --id "$APP_ID" --federated-credential-id "$name" \
    --query subject -o tsv 2>/dev/null || true)

  if [ "$current" = "$subject" ]; then
    echo "exists:  federated credential $name"
    return
  fi

  local params="{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"description\": \"GitHub Actions OIDC for $GITHUB_ORG/$INFRA_REPO\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

  if [ -n "$current" ]; then
    az ad app federated-credential update --id "$APP_ID" \
      --federated-credential-id "$name" --parameters "$params" --output none
    echo "updated: federated credential $name"
    echo "           was: $current"
    echo "           now: $subject"
  else
    az ad app federated-credential create --id "$APP_ID" --parameters "$params" --output none
    echo "created: federated credential $name -> $subject"
  fi
}

banner "Federated credentials"
add_federated_credential "github-main"     "${SUB_PREFIX}:ref:refs/heads/main"
add_federated_credential "github-env-dev"  "${SUB_PREFIX}:environment:dev"
add_federated_credential "github-env-prod" "${SUB_PREFIX}:environment:production"

# --- Role assignments ---------------------------------------------------------

assign_role() {
  local role="$1" scope="$2"
  if az role assignment list --assignee "$SP_OBJECT_ID" --role "$role" --scope "$scope" \
      --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
    echo "exists:  $role on ${scope##*/}"
  else
    az role assignment create --assignee-object-id "$SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "$role" --scope "$scope" --output none
    echo "created: $role on ${scope##*/}"
  fi
}

banner "Role assignments"
# images: Packer builds and publishes here; gallery-prune.py deletes versions.
# tfstate: state, plus storage-key fallback. The others: Terraform and the
# workflows' az calls (DB sync, SAS tokens, VMSS start/stop, run-command).
for rg in "${ALL_RGS[@]}"; do
  assign_role "Contributor" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$rg"
done

# Contributor cannot write role assignments. production/ and dev/ grant their
# VM identities Key Vault Secrets User on the vault in this group, and dev does
# it on every deploy because the dev VM is recreated each time.
assign_role "Role Based Access Control Administrator" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SECRETS_RG"

# CI runs Terraform with use_azuread_auth (ARM_USE_AZUREAD in the workflows), so
# state reads and blob leases need a data-plane role. Contributor does not grant
# one.
assign_role "Storage Blob Data Contributor" "$STORAGE_ID"

if [ -n "$PUBLIC_IP_ID" ]; then
  # Scoped to the one IP, not dns-test-rg.
  assign_role "Network Contributor" "$PUBLIC_IP_ID"
else
  echo "WARNING: PUBLIC_IP_ID is unset - skipping the load balancer IP grant." >&2
  echo "         Fine only if Terraform creates the LB's public IP itself." >&2
fi

for rg in $CONSUMER_RESOURCE_GROUPS; do
  if az group show --name "$rg" >/dev/null 2>&1; then
    assign_role "Reader" "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$rg"
  else
    echo "skip:    Reader on $rg (group does not exist yet)"
  fi
done

# --- Legacy grants left by the original bootstrap ------------------------------

banner "Legacy check"
LEGACY_SUB_ROLE=$(az role assignment list --assignee "$SP_OBJECT_ID" --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --query "[?scope=='/subscriptions/$SUBSCRIPTION_ID'].id | [0]" -o tsv 2>/dev/null || true)
PASSWORD_COUNT=$(az ad app credential list --id "$APP_ID" --query "length(@)" -o tsv 2>/dev/null || echo 0)

if [ -n "$LEGACY_SUB_ROLE" ]; then
  echo "LEGACY:  $SP_NAME still holds Contributor on the whole subscription."
else
  echo "ok:      no subscription-scope Contributor"
fi
if [ "${PASSWORD_COUNT:-0}" != "0" ]; then
  echo "LEGACY:  $SP_NAME still has $PASSWORD_COUNT password credential(s)."
else
  echo "ok:      no password credentials"
fi

# --- Summary ------------------------------------------------------------------

banner "Bootstrap complete"
cat <<EOF

Repository secrets (no AZURE_CLIENT_SECRET - workflows log in with OIDC):

  gh secret set AZURE_CLIENT_ID       --repo $GITHUB_ORG/$INFRA_REPO --body "$APP_ID"
  gh secret set AZURE_TENANT_ID       --repo $GITHUB_ORG/$INFRA_REPO --body "$TENANT_ID"
  gh secret set AZURE_SUBSCRIPTION_ID --repo $GITHUB_ORG/$INFRA_REPO --body "$SUBSCRIPTION_ID"
  gh secret set SSH_PUBLIC_KEY        --repo $GITHUB_ORG/$INFRA_REPO --body "\$(cat ~/.ssh/id_ed25519.pub)"

Repository variables:

  gh variable set GALLERY_NAME             --repo $GITHUB_ORG/$INFRA_REPO --body "$GALLERY_NAME"
  gh variable set GALLERY_RESOURCE_GROUP   --repo $GITHUB_ORG/$INFRA_REPO --body "$IMAGES_RG"
  gh variable set LOCATION                 --repo $GITHUB_ORG/$INFRA_REPO --body "$LOCATION"
  gh variable set TF_STATE_RESOURCE_GROUP  --repo $GITHUB_ORG/$INFRA_REPO --body "$TFSTATE_RG"
  gh variable set TF_STATE_STORAGE_ACCOUNT --repo $GITHUB_ORG/$INFRA_REPO --body "$STORAGE_NAME"

Set after the matching terraform apply: DEVTEST_DB_HOST, DEVTEST_STORAGE_ACCOUNT,
SUBNET_ID, DRUPAL_SITE_UUID, DOMAIN_NAME, PUBLIC_IP_ID, LB_DNS_LABEL.

environments/secrets/ needs the SP object ID: $SP_OBJECT_ID
EOF

if [ -n "$LEGACY_SUB_ROLE" ] || [ "${PASSWORD_COUNT:-0}" != "0" ]; then
  cat <<EOF

LEGACY CLEANUP - only after base-image-build, a dev merge, a main merge and a
gallery-prune dry run have all run green on OIDC:

  # 1. Drop the subscription-wide role. Undo: az role assignment create
  #    --assignee-object-id $SP_OBJECT_ID --assignee-principal-type ServicePrincipal
  #    --role Contributor --scope /subscriptions/$SUBSCRIPTION_ID
  az role assignment delete --assignee $SP_OBJECT_ID --role Contributor \\
    --scope /subscriptions/$SUBSCRIPTION_ID

  # 2. Drop the password and the GitHub secret that held it.
  az ad app credential list --id $APP_ID -o table
  az ad app credential delete --id $APP_ID --key-id <keyId from the list>
  gh secret delete AZURE_CLIENT_SECRET --repo $GITHUB_ORG/$INFRA_REPO
EOF
fi
