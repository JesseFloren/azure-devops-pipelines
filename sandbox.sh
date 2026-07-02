SUBSCRIPTION_ID="04a8f402-d4f5-4042-9078-601df774d3e0"
ENV_SHORT="dev"
SP_OBJECT_ID="312056e2-53e7-4404-a16e-be1cbe40dff4"
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

az role assignment list \
  --assignee-object-id "$SP_OBJECT_ID" \
  --scope "$ST_SCOPE" \
  --query "[].roleDefinitionName" -o tsv