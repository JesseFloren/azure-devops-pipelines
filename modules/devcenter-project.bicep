targetScope = 'resourceGroup'

@description('Dev Center name.')
param devCenterName string

@description('Dev Center Project name.')
param devCenterProjectName string

@description('Deployment location.')
param location string

@description('Environment full name.')
param environment string

@description('Tags applied to resources.')
param tags object = {}

resource devCenter 'Microsoft.DevCenter/devcenters@2024-02-01' = {
  name: devCenterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

resource devCenterProject 'Microsoft.DevCenter/projects@2024-02-01' = {
  name: devCenterProjectName
  location: location
  tags: tags
  properties: {
    devCenterId: devCenter.id
    description: 'Managed DevOps Pools project for ${environment} environment.'
  }
}

output devCenterName string = devCenter.name
output devCenterId string = devCenter.id
output devCenterProjectName string = devCenterProject.name
output devCenterProjectId string = devCenterProject.id
