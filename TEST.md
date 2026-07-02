# TEST.md — Validate private Storage access from Managed DevOps Pool

This guide describes the **extra setup required for testing** and provides an Azure Pipeline that verifies your agents can access data in the PCT storage account through the private endpoint.

## Goal

Run a pipeline on `man-<env>-devops-mdp001` that:

1. Authenticates to Azure.
2. Uses data-plane operations against the PCT storage account.
3. Uploads and reads a test blob successfully.

If this succeeds, private connectivity + DNS + RBAC are working.

---

## 1) Required extra setup

### 1.1 Azure DevOps service connection

Create an Azure Resource Manager service connection in Azure DevOps (for example: `sc-man-devops`).

The service principal used by this service connection must be able to access:

- Resource group: `man-<env>-pct-rg001`
- Storage account: `man<env-shorthand>pctst001`

### 1.2 RBAC required for storage data operations

For blob read/write tests, assign **Storage Blob Data Contributor** to the service connection principal on the storage account scope.

Optional but commonly useful:

- `Reader` on the storage account (management-plane read)

> Important: management-plane roles (like `Contributor`) do **not** grant blob data access.
> For this pipeline, you need a Storage **Data** role.

Example (replace values):

```bash
SUBSCRIPTION_ID="<subscription-id>"
ENV_SHORT="dev"
SP_OBJECT_ID="<service-connection-sp-object-id>"
STORAGE_ACCOUNT="man${ENV_SHORT}pctst001"

ST_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/man-${ENV_SHORT}-pct-rg001/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$ST_SCOPE"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Reader" \
  --scope "$ST_SCOPE"
```

Use the least-privilege option where possible. For this specific blob test, `Storage Blob Data Contributor` is typically sufficient.

### 1.2.1 Troubleshooting this exact permission error

If you see:

`You do not have the required permissions needed to perform this operation...`

then the identity used by `azureSubscription` in the pipeline does not have the required Storage Data role on the storage account scope.

Verify assignments:

```bash
SUBSCRIPTION_ID="<subscription-id>"
ENV_SHORT="dev"
SP_OBJECT_ID="<service-connection-sp-object-id>"
STORAGE_ACCOUNT="man${ENV_SHORT}pctst001"
ST_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/man-${ENV_SHORT}-pct-rg001/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"

az role assignment list \
  --assignee-object-id "$SP_OBJECT_ID" \
  --scope "$ST_SCOPE" \
  --query "[].roleDefinitionName" -o tsv
```

Expected at minimum for this test:

- `Storage Blob Data Contributor`

After assigning roles, wait a few minutes for RBAC propagation and rerun the pipeline.

### 1.3 Agent pool selection

Use the Managed DevOps Pool in your pipeline:

- `pool: name: man-<env>-devops-mdp001`

### 1.4 Network preconditions

Before running the test pipeline, ensure:

- MDP VNet ↔ PCT VNet peering is deployed in both directions.
- Private DNS zone link exists for both VNets.
- Storage account public network access is disabled (as intended).

---

## 2) Azure Pipeline test

### Why the private endpoint is not explicitly referenced

The pipeline targets the storage account name (`man<env-shorthand>pctst001`), not the private endpoint resource ID.
That is expected behavior for Blob data-plane operations.

Private connectivity is enforced by infrastructure:

- The storage account has `publicNetworkAccess: Disabled`.
- A private endpoint exists for the `blob` subresource.
- Private DNS (`privatelink.blob.<storage-suffix>`) is linked to both VNets.

Because of this, requests from the MDP agent resolve the storage endpoint to the private endpoint path automatically.

Use [azure-pipelines-storage-private-test.yml](azure-pipelines-storage-private-test.yml) from this repo, or create an Azure DevOps pipeline from it:

```yaml
trigger: none
pr: none

pool:
  name: man-dev-devops-mdp001

variables:
  azureServiceConnection: sc-man-pct
  envShort: dev
  storageAccountName: man$(envShort)pctst001
  storageContainerName: pe-connectivity-test
  testBlobName: mdp-private-endpoint-test.txt

stages:
- stage: PrivateStorageConnectivity
  displayName: Validate private storage connectivity
  jobs:
  - job: BlobReadWrite
    displayName: Upload and read blob via private endpoint path
    steps:
    - checkout: self

    - task: AzureCLI@2
      displayName: Blob write/read test
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          set -euo pipefail

          echo "Using storage account: $(storageAccountName)"
          az storage account show --name "$(storageAccountName)" --query "{name:name,publicNetworkAccess:publicNetworkAccess}" -o table

          # Optional visibility check: show how blob endpoint resolves from this agent.
          BLOB_FQDN=$(az storage account show --name "$(storageAccountName)" --query "primaryEndpoints.blob" -o tsv | sed -E 's#https?://([^/]+)/?#\1#')
          echo "Blob endpoint FQDN: ${BLOB_FQDN}"
          nslookup "${BLOB_FQDN}" || true

          # Create container if it does not exist.
          az storage container create \
            --name "$(storageContainerName)" \
            --account-name "$(storageAccountName)" \
            --auth-mode login \
            --only-show-errors 1>/dev/null

          echo "Managed DevOps Pool private endpoint connectivity test $(date -u +%FT%TZ)" > test.txt

          # Upload blob.
          az storage blob upload \
            --container-name "$(storageContainerName)" \
            --name "$(testBlobName)" \
            --file test.txt \
            --account-name "$(storageAccountName)" \
            --auth-mode login \
            --overwrite true \
            --only-show-errors

          # Download blob and compare content.
          az storage blob download \
            --container-name "$(storageContainerName)" \
            --name "$(testBlobName)" \
            --file downloaded.txt \
            --account-name "$(storageAccountName)" \
            --auth-mode login \
            --only-show-errors

          diff -u test.txt downloaded.txt
          echo "SUCCESS: Blob upload/download works from MDP agent."
```

---

## 3) Expected outcome

Pipeline succeeds and prints:

- `SUCCESS: Blob upload/download works from MDP agent.`

If it fails with authorization errors, re-check RBAC assignments.
If it fails with connectivity or DNS-style errors, re-check peering and private DNS links.

### 3.1 If container creation works, but upload/download fails

If `az storage container create` succeeds, then your pipeline can usually:

- authenticate to Azure,
- reach the Blob endpoint, and
- perform at least basic data-plane calls.

That means the issue is often one of these:

1. the pipeline identity is different from the principal that received RBAC,
2. RBAC assignment has not fully propagated yet,
3. the failing blob command hides useful details because of `--only-show-errors`.

Use this diagnostic block in the same AzureCLI task:

```bash
set -euo pipefail

echo "Authenticated principal/context:"
az account show --query "{subscription:id, tenant:tenantId, user:user.name, type:user.type}" -o json

echo "List blobs before upload (should work with Storage Blob Data Contributor):"
az storage blob list \
  --container-name "$(storageContainerName)" \
  --account-name "$(storageAccountName)" \
  --auth-mode login -o table

echo "Upload test blob with verbose output:"
az storage blob upload \
  --container-name "$(storageContainerName)" \
  --name "$(testBlobName)" \
  --file test.txt \
  --account-name "$(storageAccountName)" \
  --auth-mode login \
  --overwrite true

echo "Download test blob with verbose output:"
az storage blob download \
  --container-name "$(storageContainerName)" \
  --name "$(testBlobName)" \
  --file downloaded.txt \
  --account-name "$(storageAccountName)" \
  --auth-mode login
```

Tip: temporarily remove `--only-show-errors` while troubleshooting so the precise server-side error is visible in logs.

---

## 4) Optional hardening for test scope

- Use a dedicated container (already shown).
- Remove the blob/container after the test run.
- Consider using `Storage Blob Data Reader` instead of contributor when you only need read validation.
