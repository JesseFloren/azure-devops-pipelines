/*
  main.bicepparam — Managed DevOps Pools parameter file
  Edit this file to configure the deployment for each environment/organisation.
*/

using 'main.bicep'

// ─── Environment ──────────────────────────────────────────────────────────────

param environment = 'Development'

// ─── Location ─────────────────────────────────────────────────────────────────

param location = 'westeurope'

// ─── Network ──────────────────────────────────────────────────────────────────
// Ensure the address space does not conflict with other spoke/hub VNets.

param vnetAddressPrefix = '10.100.0.0/24'
param mdpSubnetPrefix   = '10.100.0.0/26'   // 64 IPs — enough for concurrent MDP agents

// ─── Private Connectivity Test ─────────────────────────────────────────────

param pctVnetAddressPrefix = '10.101.0.0/24'
param pctSubnetPrefix      = '10.101.0.0/27'

// ─── Managed DevOps Pool ─────────────────────────────────────────────────────

param mdpAgentVmSku         = 'Standard_B2als_v2'  // 4 vCPU / 16 GiB; replace with desired VM size
param mdpMaxAgentCount      = 1                   // maximum concurrent agents / ADO parallelism
param mdpOsType             = 'ubuntu'
param mdpWellKnownImageName = 'ubuntu-22.04/latest'

// ─── Azure DevOps ─────────────────────────────────────────────────────────────
// Replace with your actual Azure DevOps organisation URL.

param azureDevOpsOrganizationUrl = 'https://dev.azure.com/floren-dev'
param azureDevOpsProjects        = []               // empty = pool available to all projects

// ─── SKUs ─────────────────────────────────────────────────────────────────────

param publicIpSku = 'Standard'   // Standard is required for NAT Gateway
param pctStorageAccountSku = 'Standard_LRS'
