/*
  pct-resources.bicep — resources deployed into the man-{env}-pct-rg001 resource group.

  Resources:
    - Virtual Network     (AVM) — hosts the private-endpoint subnet
    - Storage Account     (AVM) — private connectivity test target
    - Private DNS Zone    (AVM) — resolves the storage private endpoint name
*/

import { getName, getStorageAccountName } from '../macros/naming.bicep'
import { getEnvShorthand } from '../macros/environments.bicep'

@description('Azure region for all resources.')
param location string

@description('Full environment name: Production | Acceptance | Test | Development')
@allowed(['Production', 'Acceptance', 'Test', 'Development'])
param environment string

@description('Common resource tags.')
param tags object

@description('Application shorthand (3-5 chars). Fixed: man.')
param appShorthand string

@description('Resource-group shorthand. Fixed: pct.')
param rgShorthand string

@description('Address space of the PCT VNet (CIDR).')
param vnetAddressPrefix string

@description('Address prefix of the subnet dedicated to private endpoints. Must be within vnetAddressPrefix.')
param privateEndpointSubnetPrefix string

@description('SKU name for the storage account.')
param pctStorageAccountSku string = 'Standard_LRS'

@description('Resource ID of the MDP VNet that needs access to the private endpoint.')
param mdpVnetResourceId string

var envShorthand = getEnvShorthand(environment)

var names = {
  vnet: getName(appShorthand, envShorthand, rgShorthand, 'vnet', '001')
  subnet: getName(appShorthand, envShorthand, rgShorthand, 'snet', '001')
  storageAccount: getStorageAccountName(appShorthand, envShorthand, rgShorthand, 'st', '001')
  privateDnsZoneLink: getName(appShorthand, envShorthand, rgShorthand, 'dnslink', '001')
}

module vnet 'br/public:avm/res/network/virtual-network:0.8.1' = {
  name: 'pct-vnet'
  params: {
    name: names.vnet
    location: location
    tags: tags
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: names.subnet
        addressPrefix: privateEndpointSubnetPrefix
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
  }
}

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.1' = {
  name: 'pct-private-dns-zone'
  params: {
    name: 'privatelink.blob.${az.environment().suffixes.storage}'
    location: 'global'
    tags: tags
    virtualNetworkLinks: [
      {
        name: names.privateDnsZoneLink
        location: 'global'
        registrationEnabled: false
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
      {
        name: getName(appShorthand, envShorthand, 'mdp', 'dnslink', '001')
        location: 'global'
        registrationEnabled: false
        virtualNetworkResourceId: mdpVnetResourceId
      }
    ]
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'pct-storage-account'
  params: {
    name: names.storageAccount
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: pctStorageAccountSku
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        name: getName(appShorthand, envShorthand, rgShorthand, 'pe', '001')
        service: 'blob'
        subnetResourceId: '${vnet.outputs.resourceId}/subnets/${names.subnet}'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              name: 'blob'
              privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
  }
}

output vnetResourceId string = vnet.outputs.resourceId
output subnetResourceId string = '${vnet.outputs.resourceId}/subnets/${names.subnet}'
output storageAccountResourceId string = storageAccount.outputs.resourceId
output privateEndpointResourceId string = '${storageAccount.outputs.resourceId}/privateEndpoints/${getName(appShorthand, envShorthand, rgShorthand, 'pe', '001')}'
output privateDnsZoneResourceId string = privateDnsZone.outputs.resourceId
