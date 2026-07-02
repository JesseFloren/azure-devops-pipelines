# Manual Steps — Managed DevOps Pools

This document lists all steps that cannot be automated through Bicep/ARM due to Azure policy or permission requirements (role assignments, app registrations, etc.).

## Execution order (important)

Follow this exact sequence to avoid confusion:

1. Register required resource providers and validate quotas.
2. Run the Bicep deployment once to create baseline resources (including VNets and Dev Center identity).
3. Expect the first run to fail on missing role assignments.
4. Apply required role assignments (VNet + Dev Center identity).
5. Re-run the same deployment command.

This order is required because:

- The VNet must exist before VNet-scoped role assignments can be created.
- The Dev Center system-assigned identity (`principalId`) only exists after the resource is created.

---

## 1. Pre-deployment: Register Resource Providers

Run the following commands once per subscription before deploying:

  
```bash
az provider register --namespace Microsoft.DevCenter
az provider register --namespace Microsoft.DevOpsInfrastructure
```

Verify registration status:

```bash
az provider show --namespace Microsoft.DevCenter        --query "registrationState"
az provider show --namespace Microsoft.DevOpsInfrastructure --query "registrationState"
```

### 1.1 Validate Managed DevOps Pools SKU availability and quota

Before deployment, validate that your selected **Managed DevOps Pools SKU/capacity** is available in the target region and subscription, and that quota is sufficient for your target parallelism.

Use Azure Portal:

1. Go to **Subscriptions** → your subscription (`flr-sandbox`) → **Usage + quotas**.
2. Filter/search on **Managed DevOps Pools** quotas in `westeurope`.
3. Confirm your intended pool capacity is available.
4. If quota is insufficient, request a quota increase before deployment.

> Note: Managed DevOps Pools quota is separate from standard VM compute SKU quota.

```

---

## 2. First deployment run (expected to fail on RBAC)

Run deployment once to create baseline resources:

```bash
az deployment sub create \
  --name "mdp-deployment-$(date +%Y%m%d%H%M)" \
  --location westeurope \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Expected behavior on first run:

- Deployment may fail because required role assignments are not yet present.
- This is normal for initial setup.
- After this run, the required targets for role assignment exist (VNet + Dev Center identity).

---

## 3. Post-first-run: RBAC — `DevOpsInfrastructure` service principal on the VNet

For **agents injected into an existing virtual network**, the Microsoft-managed enterprise application **`DevOpsInfrastructure`** must have access to the **Virtual Network** used by the pool.

Grant the following roles on the **VNet scope**:

- `Reader`
- `Network Contributor`

> **Why**: Managed DevOps Pools needs to read the VNet and join the delegated subnet, including creating the required service association link on the subnet.

> **Important**:
>
> - `Owner` on the subscription or resource group is **not normally required** for the Managed DevOps Pools service principal.
> - `Owner` or `User Access Administrator` is only needed by the **person or deployment identity creating role assignments**.

Steps:

1. Find the `DevOpsInfrastructure` service principal object ID:
  ```bash
  az ad sp list --display-name "DevOpsInfrastructure" --query "[0].id" -o tsv
  ```

2. Define the Virtual Network scope (replace `<env-short>` with your environment like `dev`, `tst`, `acc`, `prd`):
  ```bash
  VNET_SCOPE=/subscriptions/04a8f402-d4f5-4042-9078-601df774d3e0/resourceGroups/man-<env-short>-devops-rg001/providers/Microsoft.Network/virtualNetworks/man-<env-short>-devops-vnet001
  ```

3. Assign the `Reader` role on the VNet:
  ```bash
  az role assignment create \
    --assignee ceda522c-8a56-4353-9bee-79725118a96d \
    --role "Reader" \
    --scope "$VNET_SCOPE"
  ```

4. Assign the `Network Contributor` role on the VNet:
  ```bash
  az role assignment create \
    --assignee ceda522c-8a56-4353-9bee-79725118a96d \
    --role "Network Contributor" \
    --scope "$VNET_SCOPE"
  ```

If your organisation uses least-privilege custom roles, you can replace `Network Contributor` with a custom role that includes at minimum:

- `Microsoft.Network/virtualNetworks/*/read`
- `Microsoft.Network/virtualNetworks/subnets/join/action`
- `Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/validate/action`
- `Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/write`
- `Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks/delete`

---

## 4. Post-first-run: RBAC — Dev Center System Assigned Identity

After the first deployment run, the Dev Center resource (`man-{env}-devops-dc001`) has a **System Assigned Managed Identity**. This identity requires the `Contributor` role on the resource group.

```bash
# Retrieve the Dev Center's managed identity object ID after deployment
# Replace <env-short> with your environment like dev, tst, acc, prd
DC_PRINCIPAL=$(az devcenter admin devcenter show \
  --name man-<env-short>-devops-dc001 \
  --resource-group man-<env-short>-devops-rg001 \
  --query "identity.principalId" -o tsv)

az role assignment create \
  --assignee "$DC_PRINCIPAL" \
  --role "Contributor" \
  --scope /subscriptions/04a8f402-d4f5-4042-9078-601df774d3e0/resourceGroups/man-<env-short>-devops-rg001
```

---

## 5. Redeploy after RBAC assignments

After applying both RBAC sections above, re-run the same deployment command:

```bash
az deployment sub create \
  --name "mdp-deployment-$(date +%Y%m%d%H%M)" \
  --location westeurope \
  --template-file main.bicep \
  --parameters main.bicepparam
```

This run should complete successfully if role assignments and quotas are correct.

---

## 6. Post-deployment: Link Pool to Azure DevOps Organisation

After Bicep deployment completes, the Managed DevOps Pool must be registered as an **Agent Pool** in the Azure DevOps organisation.

1. Navigate to: `https://dev.azure.com/<your-organisation>/_settings/agentpools`
2. Click **Add pool** → choose **Azure Managed DevOps Pools**.
3. Select the pool `man-{env}-devops-mdp001` from the dropdown.
4. Optionally restrict access to specific projects.
5. Save.

> The pool will appear as a self-hosted agent pool and can be referenced in pipelines using `pool: name: man-{env}-devops-mdp001`.

---

## 7. Post-deployment: RBAC — Azure DevOps Service Connection

The MDP needs access to the Azure DevOps organisation through its **Entra ID application**.

1. In Azure DevOps: **Organisation Settings → Entra ID** — ensure the tenant is connected.
2. In **Azure DevOps → Organisation Settings → Agent Pools → {pool} → Security** — grant build service accounts appropriate permissions.

---

## 8. Agent Image Configuration

The `resources/mdp-resources.bicep` uses `wellKnownImageName` for the `images` block in the MDP fabric profile. Configure this through `main.bicepparam` using `mdpWellKnownImageName`.

### Option A — Use well-known Microsoft images (recommended)

Set `mdpWellKnownImageName` in `main.bicepparam`, for example:

```
ubuntu-22.04/latest
windows-2022/latest
```

### Option B — Use a custom image from Azure Compute Gallery

1. Create an **Azure Compute Gallery** in your image-building subscription.
2. Create and publish a **VM Image Definition** with your custom tooling.
3. Share the gallery with the DevOps resource group (read access).
4. Replace the image block in `resources/mdp-resources.bicep` to use `resourceId` instead of `wellKnownImageName`.

---

## 9. Networking — Hub/Spoke Peering (if applicable)

The peering between the MDP VNet and the new PCT VNet is now created by Bicep.
Use the following steps only if you also need additional hub/spoke peering to an external network.

If this VNet should be peered to the **Management Hub VNet** (for connectivity to on-premises or shared services):

1. Create a VNet peering from the MDP VNet to the hub VNet.
2. Create a VNet peering from the hub VNet back to the MDP VNet.
3. If using Azure Firewall in the hub, create a UDR on the MDP subnet to route traffic through the firewall's private IP.
4. Add the required Azure Firewall / NSG rules for the MDP agent traffic.

---

## 10. (Optional) Monitoring & Alerts

Create diagnostic settings and alerts for:

- **Managed DevOps Pool**: agent queue depth, agent failures.
- **NAT Gateway**: connection counts, dropped packets.
- **VNet**: flow logs via Network Watcher.

These are recommended via Azure Monitor / Log Analytics but are not included in this Bicep deployment.

---

## 11. AVM Module Version Verification

Before deploying, verify the latest versions of the AVM modules used in this project against the [AVM registry](https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/):

| Module                                         | Version used | Check latest |
|------------------------------------------------|-------------|--------------|
| `avm/res/network/network-security-group`       | `0.5.0`     | [link](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/network-security-group) |
| `avm/res/network/public-ip-address`            | `0.6.0`     | [link](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/public-ip-address) |
| `avm/res/network/nat-gateway`                  | `1.2.0`     | [link](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/nat-gateway) |
| `avm/res/network/virtual-network`              | `0.4.0`     | [link](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network) |
| `avm/res/dev-ops-infrastructure/pool`          | `0.2.0`     | [link](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/dev-ops-infrastructure/pool) |

Update the `br/public:avm/res/...:<version>` references in `resources/mdp-resources.bicep` if newer versions are available.

---

## 12. Deployment Command (repeatable)

```bash
az deployment sub create \
  --name "mdp-deployment-$(date +%Y%m%d%H%M)" \
  --location westeurope \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## 13. Test Validation Guide

For the end-to-end private connectivity validation from Azure DevOps pipelines (including required storage RBAC for the service account), see [TEST.md](TEST.md).
