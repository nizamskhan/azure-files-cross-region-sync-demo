# Scenario 2 - Private Endpoint Container Apps Job

This scenario copies Azure Files from **West Europe** to **North Europe** when both storage accounts have **public network access disabled**.

It uses:

- Azure Files storage accounts behind private endpoints.
- Private DNS zone `privatelink.file.core.windows.net`.
- Azure Container Apps Environment integrated with a VNet.
- Scheduled Azure Container Apps Job.
- A named Log Analytics workspace for Container Apps logs.
- AzCopy running inside a container.
- User-assigned managed identity for Azure Files RBAC and ACR pull.

No storage account keys or SAS tokens are used by the scheduled copy job.

## Why not Azure Automation cloud runbook?

Azure Automation cloud sandboxes are not deployed into your VNet. If storage accounts are reachable only over private endpoints, the sandbox cannot resolve and reach those endpoints. The compute running AzCopy must be in, or connected to, the private network.

## Can Azure Container Apps be private?

Yes. Azure Container Apps can run in a VNet-integrated environment. A scheduled Container Apps Job does not need public ingress and can use VNet outbound connectivity to reach storage private endpoints.

## Alternatives

| Option | Works with private endpoints? | Notes |
|---|---:|---|
| Azure Automation cloud sandbox | No | Cannot be placed directly into the customer's VNet. |
| Azure Automation Hybrid Runbook Worker | Yes | Good if the customer already operates private worker VMs. |
| Azure Container Apps Job | Yes | Recommended for this scenario. |
| Azure Functions with VNet integration | Yes | Viable; requires function deployment packaging. |
| Linux App Service with VNet integration | Yes | Viable, but less natural for scheduled one-shot copy jobs. |
| VM or VM Scale Set | Yes | Simple, but higher operational overhead. |

## Deploy

Set variables:

```bash
export SUBSCRIPTION_ID="<customer-subscription-id>"
export RG="rg-azfiles-private-sync-demo"
export PREFIX="<globally-unique-lowercase-prefix>"

export SRC_STORAGE="${PREFIX}src"
export DST_STORAGE="${PREFIX}dst"
export ACR_NAME="${PREFIX}acr"
export IDENTITY_NAME="${PREFIX}-sync-mi"
export CONTAINERAPPS_ENV="${PREFIX}-cae"
export CONTAINERAPP_JOB="${PREFIX}-azfiles-sync-job"
export LOG_ANALYTICS_WORKSPACE="${PREFIX}-law"

export SRC_SHARE="sourcefiles"
export DST_SHARE="destfiles"
```

Run:

```bash
chmod +x scripts/deploy-private-containerapp-job.sh
./scripts/deploy-private-containerapp-job.sh
```

The script creates a deterministic Log Analytics workspace named by `LOG_ANALYTICS_WORKSPACE` and passes it explicitly to the Container Apps environment. This avoids Azure CLI auto-generating a new random workspace if environment creation is retried.

## Upload sample data

Because public access is disabled, run this from a machine that can resolve and reach the source storage private endpoint:

```bash
chmod +x scripts/upload-sample-data-private.sh
./scripts/upload-sample-data-private.sh
```

## Run manually

```bash
az containerapp job start \
  --name "$CONTAINERAPP_JOB" \
  --resource-group "$RG"
```

## View executions and logs

```bash
az containerapp job execution list \
  --name "$CONTAINERAPP_JOB" \
  --resource-group "$RG" \
  -o table

az containerapp job logs show \
  --name "$CONTAINERAPP_JOB" \
  --resource-group "$RG" \
  --follow
```

## Validate destination files

Run this from a machine that can resolve and reach the destination storage private endpoint:

```bash
az storage file list \
  --auth-mode login \
  --enable-file-backup-request-intent \
  --account-name "$DST_STORAGE" \
  --share-name "$DST_SHARE" \
  -o table
```

## Copy behavior

The container runs:

```bash
azcopy login --identity --identity-client-id "$AZCOPY_AUTO_LOGIN_IDENTITY_CLIENT_ID"

azcopy copy "$SOURCE_URL" "$DESTINATION_URL" \
  --recursive=true \
  --from-to=FileFile \
  --overwrite=ifSourceNewer
```

This is a copy/update pattern. It does not delete files from the destination if they are removed from the source.
