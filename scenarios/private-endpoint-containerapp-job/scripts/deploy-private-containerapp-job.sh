#!/usr/bin/env bash
set -euo pipefail

: "${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID before running this script.}"
: "${RG:=rg-azfiles-private-sync-demo}"
: "${PREFIX:?Set PREFIX to a globally unique lowercase value.}"
: "${SRC_STORAGE:=${PREFIX}src}"
: "${DST_STORAGE:=${PREFIX}dst}"
: "${ACR_NAME:=${PREFIX}acr}"
: "${IDENTITY_NAME:=${PREFIX}-sync-mi}"
: "${CONTAINERAPPS_ENV:=${PREFIX}-cae}"
: "${CONTAINERAPP_JOB:=${PREFIX}-azfiles-sync-job}"
: "${SRC_SHARE:=sourcefiles}"
: "${DST_SHARE:=destfiles}"
: "${LOCATION:=westeurope}"
: "${DESTINATION_LOCATION:=northeurope}"
: "${VNET_NAME:=${PREFIX}-vnet}"
: "${CONTAINERAPPS_SUBNET:=containerapps-subnet}"
: "${PRIVATE_ENDPOINT_SUBNET:=private-endpoints-subnet}"
: "${PRIVATE_DNS_ZONE:=privatelink.file.core.windows.net}"
: "${LOG_ANALYTICS_WORKSPACE:=${PREFIX}-law}"

IMAGE_NAME="azfiles-sync"
IMAGE_TAG="v2"

az account set --subscription "$SUBSCRIPTION_ID"
az extension add --name containerapp --upgrade -o none

az group create --name "$RG" --location "$LOCATION" -o none

az network vnet create \
  --resource-group "$RG" \
  --name "$VNET_NAME" \
  --location "$LOCATION" \
  --address-prefixes 10.42.0.0/16 \
  --subnet-name "$CONTAINERAPPS_SUBNET" \
  --subnet-prefixes 10.42.0.0/23 \
  -o none

az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET_NAME" \
  --name "$PRIVATE_ENDPOINT_SUBNET" \
  --address-prefixes 10.42.2.0/24 \
  --private-endpoint-network-policies Disabled \
  -o none

az network vnet subnet update \
  --resource-group "$RG" \
  --vnet-name "$VNET_NAME" \
  --name "$CONTAINERAPPS_SUBNET" \
  --delegations Microsoft.App/environments \
  -o none

CONTAINERAPPS_SUBNET_ID=$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET_NAME" --name "$CONTAINERAPPS_SUBNET" --query id -o tsv)
PRIVATE_ENDPOINT_SUBNET_ID=$(az network vnet subnet show --resource-group "$RG" --vnet-name "$VNET_NAME" --name "$PRIVATE_ENDPOINT_SUBNET" --query id -o tsv)

az storage account create \
  --name "$SRC_STORAGE" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --kind FileStorage \
  --sku Premium_LRS \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --public-network-access Disabled \
  -o none

az storage account create \
  --name "$DST_STORAGE" \
  --resource-group "$RG" \
  --location "$DESTINATION_LOCATION" \
  --kind FileStorage \
  --sku Premium_LRS \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --public-network-access Disabled \
  -o none

az storage share-rm create --resource-group "$RG" --storage-account "$SRC_STORAGE" --name "$SRC_SHARE" --quota 100 --enabled-protocols SMB -o none
az storage share-rm create --resource-group "$RG" --storage-account "$DST_STORAGE" --name "$DST_SHARE" --quota 100 --enabled-protocols SMB -o none

az network private-dns zone create --resource-group "$RG" --name "$PRIVATE_DNS_ZONE" -o none
az network private-dns link vnet create \
  --resource-group "$RG" \
  --zone-name "$PRIVATE_DNS_ZONE" \
  --name "${VNET_NAME}-link" \
  --virtual-network "$VNET_NAME" \
  --registration-enabled false \
  -o none

SRC_STORAGE_ID=$(az storage account show --resource-group "$RG" --name "$SRC_STORAGE" --query id -o tsv)
DST_STORAGE_ID=$(az storage account show --resource-group "$RG" --name "$DST_STORAGE" --query id -o tsv)

az network private-endpoint create \
  --resource-group "$RG" \
  --name "${SRC_STORAGE}-file-pe" \
  --location "$LOCATION" \
  --subnet "$PRIVATE_ENDPOINT_SUBNET_ID" \
  --private-connection-resource-id "$SRC_STORAGE_ID" \
  --group-id file \
  --connection-name "${SRC_STORAGE}-file-connection" \
  -o none

az network private-endpoint create \
  --resource-group "$RG" \
  --name "${DST_STORAGE}-file-pe" \
  --location "$LOCATION" \
  --subnet "$PRIVATE_ENDPOINT_SUBNET_ID" \
  --private-connection-resource-id "$DST_STORAGE_ID" \
  --group-id file \
  --connection-name "${DST_STORAGE}-file-connection" \
  -o none

az network private-endpoint dns-zone-group create \
  --resource-group "$RG" \
  --endpoint-name "${SRC_STORAGE}-file-pe" \
  --name default \
  --private-dns-zone "$PRIVATE_DNS_ZONE" \
  --zone-name file \
  -o none

az network private-endpoint dns-zone-group create \
  --resource-group "$RG" \
  --endpoint-name "${DST_STORAGE}-file-pe" \
  --name default \
  --private-dns-zone "$PRIVATE_DNS_ZONE" \
  --zone-name file \
  -o none

az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic --admin-enabled false -o none
ACR_ID=$(az acr show --resource-group "$RG" --name "$ACR_NAME" --query id -o tsv)
ACR_LOGIN_SERVER=$(az acr show --resource-group "$RG" --name "$ACR_NAME" --query loginServer -o tsv)

az identity create --resource-group "$RG" --name "$IDENTITY_NAME" --location "$LOCATION" -o none
IDENTITY_ID=$(az identity show --resource-group "$RG" --name "$IDENTITY_NAME" --query id -o tsv)
IDENTITY_CLIENT_ID=$(az identity show --resource-group "$RG" --name "$IDENTITY_NAME" --query clientId -o tsv)
IDENTITY_PRINCIPAL_ID=$(az identity show --resource-group "$RG" --name "$IDENTITY_NAME" --query principalId -o tsv)

az role assignment create --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Storage File Data Privileged Reader" --scope "$SRC_STORAGE_ID" -o none
az role assignment create --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Storage File Data Privileged Contributor" --scope "$DST_STORAGE_ID" -o none
az role assignment create --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "AcrPull" --scope "$ACR_ID" -o none

az acr build --registry "$ACR_NAME" --image "${IMAGE_NAME}:${IMAGE_TAG}" ./container

az monitor log-analytics workspace create \
  --resource-group "$RG" \
  --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
  --location "$LOCATION" \
  -o none

LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" \
  --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
  --query customerId -o tsv)

LOG_ANALYTICS_WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RG" \
  --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
  --query primarySharedKey -o tsv)

az containerapp env create \
  --resource-group "$RG" \
  --name "$CONTAINERAPPS_ENV" \
  --location "$LOCATION" \
  --infrastructure-subnet-resource-id "$CONTAINERAPPS_SUBNET_ID" \
  --internal-only true \
  --logs-destination log-analytics \
  --logs-workspace-id "$LOG_ANALYTICS_WORKSPACE_ID" \
  --logs-workspace-key "$LOG_ANALYTICS_WORKSPACE_KEY" \
  -o none

SOURCE_URL="https://${SRC_STORAGE}.file.core.windows.net/${SRC_SHARE}"
DESTINATION_URL="https://${DST_STORAGE}.file.core.windows.net/${DST_SHARE}"

az containerapp job create \
  --resource-group "$RG" \
  --name "$CONTAINERAPP_JOB" \
  --environment "$CONTAINERAPPS_ENV" \
  --trigger-type Schedule \
  --cron-expression "0 */3 * * *" \
  --replica-timeout 3600 \
  --replica-retry-limit 1 \
  --replica-completion-count 1 \
  --parallelism 1 \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
  --user-assigned "$IDENTITY_ID" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-identity "$IDENTITY_ID" \
  --env-vars \
    "SOURCE_URL=${SOURCE_URL}" \
    "DESTINATION_URL=${DESTINATION_URL}" \
    "AZCOPY_AUTO_LOGIN_TYPE=MSI" \
    "AZCOPY_MSI_CLIENT_ID=${IDENTITY_CLIENT_ID}" \
  -o none

cat <<EOF
Private Azure Files sync deployment complete.

Resource group:              ${RG}
VNet:                        ${VNET_NAME}
Source storage account:      ${SRC_STORAGE}
Source share:                ${SRC_SHARE}
Destination storage account: ${DST_STORAGE}
Destination share:           ${DST_SHARE}
Private DNS zone:            ${PRIVATE_DNS_ZONE}
Log Analytics workspace:     ${LOG_ANALYTICS_WORKSPACE}
Container Apps environment:  ${CONTAINERAPPS_ENV}
Container Apps job:          ${CONTAINERAPP_JOB}
Managed identity:            ${IDENTITY_NAME}
ACR image:                   ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}

Start a test run:
az containerapp job start --resource-group "${RG}" --name "${CONTAINERAPP_JOB}"
EOF
