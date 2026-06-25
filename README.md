# Azure Files Cross-Region Sync Demo

This repository contains a repeatable demo for copying Azure Files from **West Europe** to **North Europe** using **Azure Automation**, **AzCopy**, and a **system-assigned managed identity**.

The demo intentionally avoids storage account SAS tokens in the scheduled copy workflow. The Automation Account authenticates with Microsoft Entra ID using `azcopy login --identity`.

## Objectives

- Create a Premium Azure Files source share in **West Europe**.
- Create a Premium Azure Files destination share in **North Europe**.
- Populate the source share with sample unstructured data.
- Create an Azure Automation Account with a system-assigned managed identity.
- Assign the managed identity the correct Azure Files data-plane RBAC roles.
- Run AzCopy from a PowerShell runbook every three hours.
- Validate that files are copied from the source share to the destination share.

## Architecture

| Component | Region | Purpose |
|---|---:|---|
| Source storage account | West Europe | Hosts the source Premium Azure Files share. |
| Destination storage account | North Europe | Hosts the destination Premium Azure Files share. |
| Azure Automation Account | West Europe | Runs the scheduled PowerShell runbook. |
| Managed identity | West Europe | Authenticates AzCopy without SAS tokens or storage keys. |
| AzCopy | Runtime download | Performs recursive Azure Files service-to-service copy. |

## Important notes

- Premium Azure Files has a minimum provisioned capacity requirement. This demo uses **100 GiB** shares.
- Storage account names must be globally unique, lowercase, and 3-24 characters.
- RBAC role assignments can take several minutes to propagate.
- The runbook uses `azcopy copy` with `--overwrite=ifSourceNewer`. It updates newer files but does not delete files from the destination when they are deleted from the source.
- AzCopy service-to-service Azure Files copy does not support the `--backup` flag. That flag is only supported for upload/download scenarios.

## Prerequisites

- Azure subscription permissions to create:
  - Resource groups
  - Storage accounts
  - Azure Files shares
  - Automation Accounts
  - Managed identity role assignments
  - Automation schedules and job schedules
- Azure CLI installed and authenticated:

```bash
az login
```

- Git Bash, macOS/Linux shell, or Azure Cloud Shell for the provided `.sh` scripts.
- Azure CLI Automation extension. If prompted by Azure CLI, allow the extension to install.

## Repository contents

| Path | Description |
|---|---|
| `scripts/create-demo-resources.sh` | Creates resource group, storage accounts, Azure Files shares, Automation Account, RBAC, runbook, and schedule. |
| `scripts/upload-sample-data.sh` | Uploads sample unstructured files to the source share using Microsoft Entra authentication. |
| `runbooks/Sync-AzureFiles-WestEurope-To-NorthEurope.ps1` | PowerShell runbook that downloads AzCopy and copies files using managed identity. |
| `sample-data/` | Small sample files for functional testing. |

## Step 1 - Clone this repository

```bash
git clone https://github.com/<your-github-account>/azure-files-cross-region-sync-demo.git
cd azure-files-cross-region-sync-demo
```

## Step 2 - Set deployment variables

Set the variables for the customer's Azure environment. Choose a globally unique lowercase prefix because Azure Storage account names are global.

```bash
export SUBSCRIPTION_ID="<customer-subscription-id>"
export RG="rg-azfilescrosregionsyncdemo"
export PREFIX="<globally-unique-lowercase-prefix>"

export SRC_STORAGE="${PREFIX}src"
export DST_STORAGE="${PREFIX}dst"
export AUTOMATION_ACCOUNT="${PREFIX}aa"

export SRC_SHARE="sourcefiles"
export DST_SHARE="destfiles"
export RUNBOOK="Sync-AzureFiles-WestEurope-To-NorthEurope"
export SCHEDULE="Every-3-Hours"
```

Example prefix:

```bash
export PREFIX="afsyncdemo123"
```

## Step 3 - Create the Azure resources

Run the resource creation script:

```bash
chmod +x scripts/create-demo-resources.sh
./scripts/create-demo-resources.sh
```

The script creates:

- Resource group in West Europe.
- Premium Azure Files source storage account in West Europe.
- Premium Azure Files destination storage account in North Europe.
- 100 GiB source file share.
- 100 GiB destination file share.
- Azure Automation Account.
- System-assigned managed identity.
- RBAC assignments:
  - Source storage account: `Storage File Data Privileged Reader`
  - Destination storage account: `Storage File Data Privileged Contributor`
- Published PowerShell runbook.
- Automation schedule that runs every three hours.

## Step 4 - Upload sample data to the source share

Run:

```bash
chmod +x scripts/upload-sample-data.sh
./scripts/upload-sample-data.sh
```

This uploads the files in `sample-data/` to the source Azure Files share using Microsoft Entra authentication.

The script grants the signed-in Azure CLI user temporary `Storage File Data Privileged Contributor` access on the source storage account so the upload can use:

```bash
az storage file upload-batch \
  --auth-mode login \
  --enable-file-backup-request-intent \
  --account-name "$SRC_STORAGE" \
  --destination "$SRC_SHARE" \
  --source "sample-data"
```

## Step 5 - Review the runbook

The runbook is in:

```text
runbooks/Sync-AzureFiles-WestEurope-To-NorthEurope.ps1
```

The key commands are:

```powershell
azcopy login --identity
azcopy copy $sourceUrl $destinationUrl --recursive=true --from-to=FileFile --overwrite=ifSourceNewer
```

The runbook downloads the current Windows AzCopy package at runtime from:

```text
https://aka.ms/downloadazcopy-v10-windows
```

If the customer's environment restricts outbound internet access from Azure Automation, host AzCopy in an approved internal location and update the runbook download URL.

## Step 6 - Run a manual validation job

Start the runbook manually:

```bash
az automation runbook start \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK"
```

Check job status:

```bash
az automation job list \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  -o table
```

Wait for the job to show `Completed`.

## Step 7 - Validate destination files

Grant the signed-in Azure CLI user read access to the destination storage account if required:

```bash
USER_ID=$(az ad signed-in-user show --query id -o tsv)
DST_ID=$(az storage account show --resource-group "$RG" --name "$DST_STORAGE" --query id -o tsv)

az role assignment create \
  --assignee-object-id "$USER_ID" \
  --assignee-principal-type User \
  --role "Storage File Data Privileged Contributor" \
  --scope "$DST_ID"
```

List the destination share:

```bash
az storage file list \
  --auth-mode login \
  --enable-file-backup-request-intent \
  --account-name "$DST_STORAGE" \
  --share-name "$DST_SHARE" \
  -o table
```

List a subfolder:

```bash
az storage file list \
  --auth-mode login \
  --enable-file-backup-request-intent \
  --account-name "$DST_STORAGE" \
  --share-name "$DST_SHARE" \
  --path docs \
  -o table
```

## Step 8 - Confirm the schedule

The runbook is linked to a schedule named `Every-3-Hours`.

```bash
az automation schedule list \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  -o table
```

The schedule is associated to the runbook using the Azure Resource Manager `jobSchedules` resource.

## Troubleshooting

### Authorization errors

If the first run fails with an authorization error, wait several minutes and rerun the job. Azure RBAC role assignment propagation is not always immediate.

### AzCopy backup flag error

Do not add `--backup` to the service-to-service copy command. For Azure Files to Azure Files copy, this can fail with:

```text
backup mode is only supported for uploads and downloads
```

### No files in destination

Confirm:

- Source share contains files.
- Automation Account managed identity exists.
- Managed identity has source reader and destination contributor roles.
- Runbook variables contain the correct storage account and share names.
- Runbook job status is `Completed`.

## Cleanup

To remove the demo resources:

```bash
az group delete --name "$RG" --yes --no-wait
```

