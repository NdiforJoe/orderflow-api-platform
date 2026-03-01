// =============================================================================
// networking.bicep
// Hub-spoke VNet topology with NSGs, peering, and private DNS zones
// ADR-003: Hub-Spoke with Azure Firewall | All PaaS via Private Endpoints
// =============================================================================

@description('Environment name (dev, prod)')
param environmentName string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Hub VNet address space')
param hubVnetAddressPrefix string = '10.0.0.0/16'

@description('Spoke VNet address space')
param spokeVnetAddressPrefix string = '10.1.0.0/16'

// =============================================================================
// NSGs
// =============================================================================

// NSG for APIM subnet
// Required ports: 3443 (management), 443 (gateway), 6390 (load balancer health)
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-apim-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
          description: 'APIM management endpoint - required by platform'
        }
      }
      {
        name: 'Allow-APIM-Gateway-Inbound'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          description: 'APIM gateway - internal VNet traffic only'
        }
      }
      {
        name: 'Allow-LB-Health'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
          description: 'Azure Load Balancer health probe'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound - explicit zero-trust'
        }
      }
    ]
  }
}

// NSG for App Service integration subnet
resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-app-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-From-APIM-Subnet'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.2.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Only APIM subnet can reach app - zero-trust enforcement'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all - backend never directly reachable'
        }
      }
    ]
  }
}

// NSG for data subnet - only app subnet can reach data tier
resource dataNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-data-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-From-App-Subnet-SQL'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.1.1.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
          description: 'SQL - app subnet only'
        }
      }
      {
        name: 'Allow-From-App-Subnet-Redis'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.1.1.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '6380'
          description: 'Redis - app subnet only'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Data tier - deny all other access'
        }
      }
    ]
  }
}

// =============================================================================
// HUB VNET
// =============================================================================

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-hub-${environmentName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [hubVnetAddressPrefix]
    }
    subnets: [
      {
        // Azure Firewall requires this exact name
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.0.0/26'
          // No NSG on firewall subnet - Azure requirement
        }
      }
      {
        name: 'snet-shared-services'
        properties: {
          addressPrefix: '10.0.1.0/24'
          // Private endpoint network policies must be disabled
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
      {
        // Azure Bastion requires this exact name
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.3.0/27'
        }
      }
    ]
  }
}

// =============================================================================
// SPOKE VNET
// =============================================================================

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-spoke-${environmentName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [spokeVnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: {
            id: appNsg.id
          }
          // Delegation required for App Service VNet integration
          delegations: [
            {
              name: 'appServiceDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-integration'
        properties: {
          addressPrefix: '10.1.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: '10.1.3.0/24'
          networkSecurityGroup: {
            id: dataNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// =============================================================================
// VNET PEERING (bidirectional)
// ADR-003: Private connectivity between hub and spoke
// =============================================================================

resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: 'peer-hub-to-spoke'
  parent: hubVnet
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    // Hub allows gateway transit so spoke can use hub's firewall
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: 'peer-spoke-to-hub'
  parent: spokeVnet
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    // Spoke uses hub gateway for egress routing
    useRemoteGateways: false
  }
  dependsOn: [hubToSpokePeering]
}

// =============================================================================
// PRIVATE DNS ZONES
// Linked to both hub and spoke so all resources resolve PE addresses
// =============================================================================

var privateDnsZones = [
  'privatelink.vaultcore.azure.net'
  'privatelink.database.windows.net'
  'privatelink.servicebus.windows.net'
  'privatelink.redis.cache.windows.net'
  'privatelink.azurecr.io'
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in privateDnsZones: {
  name: zone
  location: 'global'
}]

// Link DNS zones to Hub VNet
resource dnsZoneHubLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in privateDnsZones: {
  name: 'link-hub-${replace(zone, '.', '-')}'
  parent: dnsZones[i]
  location: 'global'
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
    registrationEnabled: false
  }
}]

// Link DNS zones to Spoke VNet
resource dnsZoneSpokeLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in privateDnsZones: {
  name: 'link-spoke-${replace(zone, '.', '-')}'
  parent: dnsZones[i]
  location: 'global'
  properties: {
    virtualNetwork: {
      id: spokeVnet.id
    }
    registrationEnabled: false
  }
}]

// =============================================================================
// OUTPUTS — consumed by other modules and main.bicep
// =============================================================================

output hubVnetId string = hubVnet.id
output hubVnetName string = hubVnet.name
output spokeVnetId string = spokeVnet.id
output spokeVnetName string = spokeVnet.name

output apimSubnetId string = hubVnet.properties.subnets[2].id
output sharedServicesSubnetId string = hubVnet.properties.subnets[1].id
output appSubnetId string = spokeVnet.properties.subnets[0].id
output integrationSubnetId string = spokeVnet.properties.subnets[1].id
output dataSubnetId string = spokeVnet.properties.subnets[2].id

output keyVaultDnsZoneId string = dnsZones[0].id
output sqlDnsZoneId string = dnsZones[1].id
output serviceBusDnsZoneId string = dnsZones[2].id
output redisDnsZoneId string = dnsZones[3].id
