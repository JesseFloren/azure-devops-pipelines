/*
  mdp-resources.bicep — all resources deployed into the man-{env}-devops-rg001 resource group.

  Resources:
    - Network Security Group  (AVM) — limits traffic on the MDP subnet
    - Public IP Address       (AVM) — Standard SKU; consumed by the NAT Gateway
    - NAT Gateway             (AVM) — provides outbound internet for pool agents
    - Virtual Network         (AVM) — hosts the MDP-delegated subnet
    - Dev Center                    — organisational container required by MDP
    - Dev Center Project            — project scope required by MDP
    - Managed DevOps Pool     (AVM) — the actual self-hosted agent pool
*/

import { getName }          from '../macros/naming.bicep'
import { getEnvShorthand }  from '../macros/environments.bicep'

// ─── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string

@description('Full environment name: Production | Acceptance | Test | Development')
@allowed(['Production', 'Acceptance', 'Test', 'Development'])
param environment string

@description('Common resource tags.')
param tags object

@description('Application shorthand (3-5 chars). Fixed: man.')
param appShorthand string

@description('Resource-group shorthand. Fixed: devops.')
param rgShorthand string

@description('Address space of the VNet (CIDR).')
param vnetAddressPrefix string

@description('Address prefix of the MDP subnet (CIDR). Must be within vnetAddressPrefix.')
param mdpSubnetPrefix string

@description('VM SKU for Managed DevOps Pool agents.')
param mdpAgentVmSku string

@description('Maximum number of concurrent agents.')
param mdpMaxAgentCount int

@description('Azure DevOps organisation URL, e.g. https://dev.azure.com/contoso')
param azureDevOpsOrganizationUrl string

@description('List of Azure DevOps project names the pool is available to. Empty = all projects.')
param azureDevOpsProjects array = []

@description('OS type for pool agents: ubuntu | windows.')
@allowed(['ubuntu', 'windows'])
param mdpOsType string

@description('''
  Well-known image name for the agent VM, e.g.:
    ubuntu-22.04/latest   (Linux — recommended)
    windows-2022/latest   (Windows Server 2022)
  Leave empty to use the latest image matching mdpOsType automatically.
  See: https://learn.microsoft.com/azure/devops/managed-devops-pools/configure-images
''')
param mdpWellKnownImageName string

@description('SKU name for the Public IP address.')
param publicIpSku string

// ─── Variables ───────────────────────────────────────────────────────────────

var envShorthand = getEnvShorthand(environment)

var names = {
  nsg:         getName(appShorthand, envShorthand, rgShorthand, 'nsg', '001')
  pip:         getName(appShorthand, envShorthand, rgShorthand, 'pip', '001')
  natGateway:  getName(appShorthand, envShorthand, rgShorthand, 'ng',  '001')
  vnet:        getName(appShorthand, envShorthand, rgShorthand, 'vnet','001')
  subnet:      getName(appShorthand, envShorthand, rgShorthand, 'snet','001')
  devCenter:   getName(appShorthand, envShorthand, rgShorthand, 'dc',  '001')
  devCenterProject: getName(appShorthand, envShorthand, rgShorthand, 'dcp', '001')
  mdpPool:     getName(appShorthand, envShorthand, rgShorthand, 'mdp', '001')
}

// ─── Network Security Group ───────────────────────────────────────────────────

module nsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'deploy-nsg'
  params: {
    name:     names.nsg
    location: location
    tags:     tags
    securityRules: [
      // ── Inbound ──────────────────────────────────────────────────────────
      {
        name: 'Allow-VNet-Inbound'
        properties: {
          priority:                 100
          direction:                'Inbound'
          access:                   'Allow'
          protocol:                 '*'
          sourceAddressPrefix:      'VirtualNetwork'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange:     '*'
          description:              'Allow all traffic within the virtual network (inbound).'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority:                 4000
          direction:                'Inbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
          description:              'Explicit deny for all remaining inbound traffic.'
        }
      }
      // ── Outbound ─────────────────────────────────────────────────────────
      {
        name: 'Allow-VNet-Outbound'
        properties: {
          priority:                 100
          direction:                'Outbound'
          access:                   'Allow'
          protocol:                 '*'
          sourceAddressPrefix:      'VirtualNetwork'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange:     '*'
          description:              'Allow all traffic within the virtual network (outbound).'
        }
      }
      {
        name: 'Allow-AzureDevOps-Outbound'
        properties: {
          priority:                 200
          direction:                'Outbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'AzureDevOps'
          destinationPortRange:     '443'
          description:              'Allow MDP agents to communicate with Azure DevOps (HTTPS).'
        }
      }
      {
        name: 'Allow-AzureMonitor-Outbound'
        properties: {
          priority:                 210
          direction:                'Outbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRange:     '443'
          description:              'Allow MDP agents to send telemetry to Azure Monitor.'
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority:                 220
          direction:                'Outbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange:     '443'
          description:              'Allow MDP agents to access Azure Storage (agent images, artifacts).'
        }
      }
      {
        name: 'Allow-Internet-HTTPS-Outbound'
        properties: {
          priority:                 300
          direction:                'Outbound'
          access:                   'Allow'
          protocol:                 'Tcp'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange:     '443'
          description:              'Allow HTTPS internet access for agents (package downloads, etc.) via NAT Gateway.'
        }
      }
      {
        name: 'Deny-All-Outbound'
        properties: {
          priority:                 4000
          direction:                'Outbound'
          access:                   'Deny'
          protocol:                 '*'
          sourceAddressPrefix:      '*'
          sourcePortRange:          '*'
          destinationAddressPrefix: '*'
          destinationPortRange:     '*'
          description:              'Explicit deny for all remaining outbound traffic.'
        }
      }
    ]
  }
}

// ─── Public IP Address ────────────────────────────────────────────────────────

module pip 'br/public:avm/res/network/public-ip-address:0.6.0' = {
  name: 'deploy-pip'
  params: {
    name:     names.pip
    location: location
    tags:     tags
    skuName:  publicIpSku          // Standard — required for NAT Gateway
    skuTier:  'Regional'
    zones: [
      1
    ]
    publicIPAllocationMethod: 'Static'
  }
}

// ─── NAT Gateway ──────────────────────────────────────────────────────────────

module natGateway 'br/public:avm/res/network/nat-gateway:1.2.0' = {
  name: 'deploy-nat-gateway'
  params: {
    name:     names.natGateway
    location: location
    tags:     tags
    zone:     1
    publicIpResourceIds: [
      pip.outputs.resourceId
    ]
  }
}

// ─── Virtual Network ──────────────────────────────────────────────────────────

module vnet 'br/public:avm/res/network/virtual-network:0.4.0' = {
  name: 'deploy-vnet'
  params: {
    name:          names.vnet
    location:      location
    tags:          tags
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name:          names.subnet
        addressPrefix: mdpSubnetPrefix
        // Delegation required for Managed DevOps Pools
        delegation: 'Microsoft.DevOpsInfrastructure/pools'
        networkSecurityGroupResourceId: nsg.outputs.resourceId
        natGatewayResourceId:           natGateway.outputs.resourceId
      }
    ]
  }
}

module devCenterProject '../modules/devcenter-project.bicep' = {
  name: 'deploy-devcenter-and-project'
  params: {
    devCenterName: names.devCenter
    devCenterProjectName: names.devCenterProject
    location: location
    environment: environment
    tags: tags
  }
}

// ─── Managed DevOps Pool ─────────────────────────────────────────────────────

module mdpPool 'br/public:avm/res/dev-ops-infrastructure/pool:0.2.0' = {
  name: 'deploy-mdp-pool'
  params: {
    name:     names.mdpPool
    location: location
    tags:     tags
    devCenterProjectResourceId: devCenterProject.outputs.devCenterProjectId
    subnetResourceId: '${vnet.outputs.resourceId}/subnets/${names.subnet}'
    organizationProfile: {
      kind: 'AzureDevOps'
      organizations: [
        {
          url:         azureDevOpsOrganizationUrl
          projects:    length(azureDevOpsProjects) > 0 ? azureDevOpsProjects : null
          parallelism: mdpMaxAgentCount
        }
      ]
    }
    agentProfile: {
      kind:            'Stateless'
      resourcePredictionsProfile: {
        predictionPreference: 'Balanced'
        kind: 'Automatic'
      }
    }
    concurrency: mdpMaxAgentCount
    fabricProfileSkuName: mdpAgentVmSku
    osProfile: {
      secretsManagementSettings: {
        observedCertificates: []
        keyExportable: false
      }
      logonType: mdpOsType == 'windows' ? 'Interactive' : 'Service'
    }
    storageProfile: {
      osDiskStorageAccountType: 'Standard'
      dataDisks: []
    }
    images: [
      {
        wellKnownImageName: empty(mdpWellKnownImageName)
          ? (mdpOsType == 'windows' ? 'windows-2022/latest' : 'ubuntu-22.04/latest')
          : mdpWellKnownImageName
        buffer: '*'
      }
    ]
  }
}

// ─── Outputs ──────────────────────────────────────────────────────────────────

@description('Resource ID of the Virtual Network.')
output vnetResourceId string = vnet.outputs.resourceId

@description('Resource ID of the MDP subnet.')
output subnetResourceId string = '${vnet.outputs.resourceId}/subnets/${names.subnet}'

@description('Resource ID of the NAT Gateway.')
output natGatewayResourceId string = natGateway.outputs.resourceId

@description('Resource ID of the Managed DevOps Pool.')
output mdpPoolResourceId string = mdpPool.outputs.resourceId

@description('Name of the Dev Center.')
output devCenterName string = devCenterProject.outputs.devCenterName

@description('Name of the Dev Center Project.')
output devCenterProjectName string = devCenterProject.outputs.devCenterProjectName
