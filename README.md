# Managed DevOps Pools deployment

This repository deploys a Managed DevOps Pools environment in Bicep and follows the naming conventions defined in [context.md](context.md).

## What is deployed

### Main DevOps resource group

The main deployment resource group is:

- `man-<env>-devops-rg001`

It contains the core Managed DevOps Pools infrastructure:

- Virtual network: `man-<env>-devops-vnet001`
- Subnet: `man-<env>-devops-snet001`
- Network security group: `man-<env>-devops-nsg001`
- Public IP address: `man-<env>-devops-pip001`
- NAT gateway: `man-<env>-devops-ng001`
- Dev Center: `man-<env>-devops-dc001`
- Dev Center Project: `man-<env>-devops-dcp001`
- Managed DevOps Pool: `man-<env>-devops-mdp001`

### Private connectivity test resource group

The private connectivity test resource group is:

- `man-<env>-pct-rg001`

It contains the network and private endpoint test setup:

- Virtual network: `man-<env>-pct-vnet001`
- Private-endpoint subnet: `man-<env>-pct-snet001`
- Storage account: `man<env-shorthand>pctst001`
- Private endpoint: `man-<env>-pct-pe001`
- Private DNS zone for Blob private link: `privatelink.blob.<storage-suffix>`

## Naming pattern

Names are generated with the shared helper in [macros/naming.bicep](macros/naming.bicep):

$$
\text{name} = \text{appShorthand} - \text{envShorthand} - \text{rgShorthand} - \text{resourceShorthand}\text{instance}
$$

For example:

- `man-prd-devops-rg001`
- `man-prd-devops-vnet001`
- `man-prd-pct-rg001`

Storage account names use the lowercase helper and omit hyphens:

- `manprdpctst001`

## Files of interest

- [main.bicep](main.bicep) — subscription-scope entrypoint that creates both resource groups and deploys all modules.
- [main.bicepparam](main.bicepparam) — environment-specific values such as address spaces and SKUs.
- [azure-pipelines-deploy.yml](azure-pipelines-deploy.yml) — Azure DevOps pipeline for subscription-scope Bicep deployment.
- [azure-pipelines-storage-private-test.yml](azure-pipelines-storage-private-test.yml) — Azure DevOps pipeline for validating private storage connectivity from the Managed DevOps Pool.
- [resources/mdp-resources.bicep](resources/mdp-resources.bicep) — main DevOps resource group deployment.
- [resources/pct-resources.bicep](resources/pct-resources.bicep) — private connectivity test deployment.
- [modules/resource-group.bicep](modules/resource-group.bicep) — reusable resource group creation module.
- [modules/vnet-peering.bicep](modules/vnet-peering.bicep) — reusable VNet peering module.
- [modules/devcenter-project.bicep](modules/devcenter-project.bicep) — Dev Center and Dev Center Project module.
- [macros/naming.bicep](macros/naming.bicep) — shared naming helpers.

## Deployment notes

- The deployment is subscription-scoped, so the resource groups are created first and then used as scopes for the resource-group deployments.
- The Managed DevOps Pools subnet delegation is handled in Bicep.
- The PCT environment is connected to the DevOps network through VNet peering and private DNS links.

## Manual follow-up

Some post-deployment actions cannot be expressed in Bicep and are documented in [MANUAL-STEPS.md](MANUAL-STEPS.md).

For private connectivity validation from the Managed DevOps Pool, use [TEST.md](TEST.md).

For Azure DevOps execution, create pipelines from [azure-pipelines-deploy.yml](azure-pipelines-deploy.yml) and [azure-pipelines-storage-private-test.yml](azure-pipelines-storage-private-test.yml).
