@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unqiue hash used in all resources.')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

@minLength(1)
@description('name used to derive service, container and dapr appid')
param containerName string

@description('image name used to pull')
param imageName string = ''

@description('port used for ingress target port and dapr app port; 0 == not set')
param ingressPort int

var resourceToken = toLower(uniqueString(subscription().id, name, location))
var tags = {
  'azd-env-name': name
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2022-03-01' existing = {
  name: 'cae-${resourceToken}'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: 'contreg${resourceToken}'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-${resourceToken}'
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-10-01' existing = {
  name: 'keyvault${resourceToken}'
}

resource containerApp 'Microsoft.App/containerApps@2022-03-01' = {
  name: 'ca-${containerName}-${resourceToken}'
  location: location
  tags: union(tags, {
      'azd-service-name': containerName
    })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: ingressPort
        transport: 'auto'
      }
      dapr: {
        enabled: true
        appId: containerName
        appProtocol: 'http'
        appPort: ingressPort
      }
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: '${containerRegistry.name}.azurecr.io'
          username: containerRegistry.name
          passwordSecretRef: 'registry-password'
        }
      ]
    }
    template: {
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      containers: [
        {
          image: imageName
          name: containerName
          env: [
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
            {
              name: 'AZURE_KEY_VAULT_ENDPOINT'
              value: keyVault.properties.vaultUri
            }
          ]
        }
      ]
    }
  }
}

resource keyVaultAccessPolicies 'Microsoft.KeyVault/vaults/accessPolicies@2021-10-01' = {
  name: '${keyVault.name}/add'
  properties: {
    accessPolicies: [
      {
        objectId: containerApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
  }
}

output CONTAINERAPP_URI string = containerApp.properties.latestRevisionFqdn
