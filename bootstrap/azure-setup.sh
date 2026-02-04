#!/bin/bash
# Azure Infrastructure Bootstrap Script for lib-main-infra
# This script sets up the foundational Azure resources needed before
# Terraform can manage the infrastructure.
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Access to the target Azure subscription
#
# Usage:
#   ./azure-setup.sh
#
# After running this script, configure GitHub repository secrets with the
# values output at the end.

set -euo pipefail

# Configuration
SUBSCRIPTION_NAME="UTK-Library-Systems"
LOCATION="eastus2"
SERVICE_PRINCIPAL_NAME="lib-main-github-actions"

# Resource groups
IMAGES_RG="lib-main-images-rg"
TFSTATE_RG="lib-main-tfstate-rg"
PRODUCTION_RG="lib-main-production-rg"

# Image gallery
GALLERY_NAME="lib_main_gallery"

echo "==================================================="
echo "lib-main-infra Azure Bootstrap"
echo "==================================================="
echo ""

# Set subscription
echo "Setting subscription to: $SUBSCRIPTION_NAME"
az account set --subscription "$SUBSCRIPTION_NAME"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Tenant ID: $TENANT_ID"
echo ""

# Create resource groups
echo "Creating resource groups..."
az group create --name "$IMAGES_RG" --location "$LOCATION" --output table
az group create --name "$TFSTATE_RG" --location "$LOCATION" --output table
az group create --name "$PRODUCTION_RG" --location "$LOCATION" --output table
echo ""

# Create image gallery
echo "Creating Azure Compute Gallery..."
az sig create \
  --resource-group "$IMAGES_RG" \
  --gallery-name "$GALLERY_NAME" \
  --location "$LOCATION" \
  --output table

# Create image definitions
echo "Creating image definitions..."
az sig image-definition create \
  --resource-group "$IMAGES_RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition drupal-base-rocky-linux-9 \
  --publisher UTKLibraries \
  --offer drupal-base \
  --sku rocky-linux-9 \
  --os-type Linux \
  --os-state Generalized \
  --hyper-v-generation V2 \
  --output table

az sig image-definition create \
  --resource-group "$IMAGES_RG" \
  --gallery-name "$GALLERY_NAME" \
  --gallery-image-definition drupal-rocky-linux-9 \
  --publisher UTKLibraries \
  --offer drupal \
  --sku rocky-linux-9 \
  --os-type Linux \
  --os-state Generalized \
  --hyper-v-generation V2 \
  --output table
echo ""

# Create Terraform state storage
echo "Creating Terraform state storage account..."
STORAGE_NAME="libmaintfstate$(openssl rand -hex 4)"
az storage account create \
  --name "$STORAGE_NAME" \
  --resource-group "$TFSTATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --allow-blob-public-access false \
  --output table

az storage container create \
  --name tfstate \
  --account-name "$STORAGE_NAME" \
  --output table
echo ""

# Check for existing service principal
echo "Checking for existing service principal..."
EXISTING_SP=$(az ad sp list --display-name "$SERVICE_PRINCIPAL_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [ -n "$EXISTING_SP" ]; then
  echo "Service principal already exists: $EXISTING_SP"
  echo "Skipping creation. Use Azure Portal to reset credentials if needed."
  CLIENT_ID="$EXISTING_SP"
  CLIENT_SECRET="<use existing or reset in Azure Portal>"
else
  echo "Creating service principal..."
  SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$SERVICE_PRINCIPAL_NAME" \
    --role Contributor \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --sdk-auth)
  CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
  CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.clientSecret')
fi
echo ""

# Output summary
echo "==================================================="
echo "Bootstrap Complete!"
echo "==================================================="
echo ""
echo "Configure GitHub repository secrets with these values:"
echo ""
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_CLIENT_ID: $CLIENT_ID"
echo "AZURE_CLIENT_SECRET: $CLIENT_SECRET"
echo ""
echo "Configure GitHub repository variables:"
echo ""
echo "GALLERY_NAME: $GALLERY_NAME"
echo "GALLERY_RESOURCE_GROUP: $IMAGES_RG"
echo "LOCATION: $LOCATION"
echo "TF_STATE_RESOURCE_GROUP: $TFSTATE_RG"
echo "TF_STATE_STORAGE_ACCOUNT: $STORAGE_NAME"
echo ""
echo "Additional secrets to configure:"
echo "  SSH_PUBLIC_KEY: (your SSH public key)"
echo "  DB_ADMIN_PASSWORD: (generate a secure password)"
echo ""
echo "IMPORTANT: Build base image first before any PR workflow!"
echo "Run: .github/workflows/base-image-build.yml manually"
echo "==================================================="
