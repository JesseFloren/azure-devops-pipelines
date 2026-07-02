/*
  main.bicep — Managed DevOps Pools deployment
  Scope   : Subscription
  App     : Management (man)
  Platform Landing Zone — Management subscription
  --------------------------------------------------
  Resources deployed:
    • Resource Group      man-{env}-devops-rg{instance}
    • Resource Group      man-{env}-pct-rg{instance}
    • NSG                 man-{env}-devops-nsg{instance}
    • Public IP           man-{env}-devops-pip{instance}
    • NAT Gateway         man-{env}-devops-ng{instance}
    • Virtual Network     man-{env}-devops-vnet{instance}
      └─ Subnet           man-{env}-devops-snet{instance}  (delegated to MDP)
    • Virtual Network     man-{env}-pct-vnet{instance}
      └─ Subnet           man-{env}-pct-snet{instance}  (private endpoints)
    • Storage Account     man{env}pctst{instance}
    • Private Endpoint    man-{env}-pct-pe{instance}
    • Dev Center          man-{env}-devops-dc{instance}
    • Dev Center Project  man-{env}-devops-dcp{instance}
    • Managed DevOps Pool man-{env}-devops-mdp{instance}
*/    

targetScope = 'subscription'

import { getName }         from 'macros/naming.bicep'
import { getEnvShorthand } from 'macros/environments.bicep'

// ─── Config ───────────────────────────────────────────────────────────────────
// Edit these variables to adapt the deployment to a different application.

var appShorthand = 'man'
var appFullName  = 'Management'
var rgShorthand  = 'devops'
var pctRgShorthand = 'pct'

// ─── Parameters ──────────────────────────────────────────────────────────────

@description('Full environment name.')
@allowed(['Production', 'Acceptance', 'Test', 'Development'])
param environment string

@description('Azure region for all resources.')
param location string

// Network ─────────────────────────────────────────────────────────────────────

@description('Address space of the Virtual Network (CIDR).')
param vnetAddressPrefix string

@description('Address prefix of the MDP subnet (CIDR). Must be within vnetAddressPrefix.')
param mdpSubnetPrefix string

@description('Address space of the PCT Virtual Network (CIDR).')
param pctVnetAddressPrefix string

@description('Address prefix of the PCT subnet dedicated to private endpoints. Must be within pctVnetAddressPrefix.')
param pctSubnetPrefix string

// Managed DevOps Pool ─────────────────────────────────────────────────────────

@description('VM SKU used for pool agents, e.g. Standard_D4ds_v5.')
param mdpAgentVmSku string

@description('Maximum number of concurrent agents (also the parallelism limit per ADO organisation).')
@minValue(1)
@maxValue(500)
param mdpMaxAgentCount int

@description('OS type for pool agents.')
@allowed(['ubuntu', 'windows'])
param mdpOsType string

@description('''Well-known image name for agents, e.g. ubuntu-22.04/latest or windows-2022/latest.
  Leave empty to auto-select based on mdpOsType.
  See: https://learn.microsoft.com/azure/devops/managed-devops-pools/configure-images''')
param mdpWellKnownImageName string = ''

@description('Azure DevOps organisation URL. Example: https://dev.azure.com/contoso')
param azureDevOpsOrganizationUrl string

@description('Azure DevOps project names available to this pool. Leave empty to allow all projects.')
param azureDevOpsProjects array = []

// SKUs ────────────────────────────────────────────────────────────────────────

@description('SKU name for the Public IP address. Must be Standard for NAT Gateway.')
param publicIpSku string

@description('SKU name for the PCT storage account.')
param pctStorageAccountSku string = 'Standard_LRS'

// ─── Derived Values ───────────────────────────────────────────────────────────

var envShorthand = getEnvShorthand(environment)
var rgName       = getName(appShorthand, envShorthand, rgShorthand, 'rg', '001')
var pctRgName    = getName(appShorthand, envShorthand, pctRgShorthand, 'rg', '001')

// ─── Tags ────────────────────────────────────────────────────────────────────

var commonTags = {
  Environment:  environment
  Application:  appFullName
  Platform:     'Management'
  DeployedBy:   'Bicep / AVM'
  ManagedBy:    'Platform Engineering'
}

// ─── Resource Group ───────────────────────────────────────────────────────────

module mdpRg 'modules/resource-group.bicep' = {
  name: 'deploy-mdp-resource-group'
  params: {
    name: rgName
    location: location
    tags: commonTags
  }
}

module pctRg 'modules/resource-group.bicep' = {
  name: 'deploy-pct-resource-group'
  params: {
    name: pctRgName
    location: location
    tags: commonTags
  }
}

// ─── Resource Deployment ─────────────────────────────────────────────────────

module mdpResources './resources/mdp-resources.bicep' = {
  name:  'mdp-resources-deployment'
  scope: resourceGroup(rgName)
  dependsOn: [
    mdpRg
  ]
  params: {
    location:                   location
    environment:                environment
    tags:                       commonTags
    appShorthand:               appShorthand
    rgShorthand:                rgShorthand
    vnetAddressPrefix:          vnetAddressPrefix
    mdpSubnetPrefix:            mdpSubnetPrefix
    mdpAgentVmSku:              mdpAgentVmSku
    mdpMaxAgentCount:           mdpMaxAgentCount
    azureDevOpsOrganizationUrl: azureDevOpsOrganizationUrl
    azureDevOpsProjects:        azureDevOpsProjects
    mdpOsType:                  mdpOsType
    mdpWellKnownImageName:      mdpWellKnownImageName
    publicIpSku:                publicIpSku
  }
}

module pctResources './resources/pct-resources.bicep' = {
  name: 'pct-resources-deployment'
  scope: resourceGroup(pctRgName)
  dependsOn: [
    pctRg
  ]
  params: {
    location:                   location
    environment:                environment
    tags:                       commonTags
    appShorthand:               appShorthand
    rgShorthand:                pctRgShorthand
    vnetAddressPrefix:          pctVnetAddressPrefix
    privateEndpointSubnetPrefix: pctSubnetPrefix
    pctStorageAccountSku:       pctStorageAccountSku
    mdpVnetResourceId:          mdpResources.outputs.vnetResourceId
  }
}

module mdpToPctPeering 'modules/vnet-peering.bicep' = {
  name: 'mdp-to-pct-peering-deployment'
  scope: resourceGroup(rgName)
  params: {
    vnetName: last(split(mdpResources.outputs.vnetResourceId, '/'))
    peeringName: 'to-pct'
    remoteVnetResourceId: pctResources.outputs.vnetResourceId
  }
}

module pctToMdpPeering 'modules/vnet-peering.bicep' = {
  name: 'pct-to-mdp-peering-deployment'
  scope: resourceGroup(pctRgName)
  params: {
    vnetName: last(split(pctResources.outputs.vnetResourceId, '/'))
    peeringName: 'to-mdp'
    remoteVnetResourceId: mdpResources.outputs.vnetResourceId
  }
}

// ─── Outputs ──────────────────────────────────────────────────────────────────

@description('Name of the resource group.')
output resourceGroupName string = rgName

@description('Name of the PCT resource group.')
output pctResourceGroupName string = pctRgName

@description('Resource ID of the Virtual Network.')
output vnetResourceId string = mdpResources.outputs.vnetResourceId

@description('Resource ID of the PCT Virtual Network.')
output pctVnetResourceId string = pctResources.outputs.vnetResourceId

@description('Resource ID of the MDP subnet.')
output subnetResourceId string = mdpResources.outputs.subnetResourceId

@description('Resource ID of the PCT subnet.')
output pctSubnetResourceId string = pctResources.outputs.subnetResourceId

@description('Resource ID of the NAT Gateway.')
output natGatewayResourceId string = mdpResources.outputs.natGatewayResourceId

@description('Resource ID of the PCT storage account.')
output pctStorageAccountResourceId string = pctResources.outputs.storageAccountResourceId

@description('Resource ID of the PCT private endpoint.')
output pctPrivateEndpointResourceId string = pctResources.outputs.privateEndpointResourceId

@description('Resource ID of the Managed DevOps Pool.')
output mdpPoolResourceId string = mdpResources.outputs.mdpPoolResourceId

@description('Name of the Dev Center.')
output devCenterName string = mdpResources.outputs.devCenterName

@description('Name of the Dev Center Project.')
output devCenterProjectName string = mdpResources.outputs.devCenterProjectName
