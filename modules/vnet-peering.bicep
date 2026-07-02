/*
  vnet-peering.bicep — creates a single VNet peering from the local VNet to a
  remote VNet.
*/

targetScope = 'resourceGroup'

@description('Name of the local virtual network in this resource group.')
param vnetName string

@description('Name of the peering resource to create under the local virtual network.')
param peeringName string

@description('Resource ID of the remote virtual network.')
param remoteVnetResourceId string

resource localVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: remoteVnetResourceId
    }
  }
}

output peeringResourceId string = peering.id
