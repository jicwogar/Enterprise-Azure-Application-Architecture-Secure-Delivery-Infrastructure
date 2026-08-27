@description('Azure Region for all resources')
param location string = 'eastus'

@description('Resource name prefix for consistent naming convention')
param prefix string = 'architect-prod'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureadmin'

@description('Admin password for the Virtual Machine')
@secure()
param adminPassword string = 'P@ssw0rd2026!AzureSecure'

// 1. Virtual Network & Subnets
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-${prefix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'appgw-subnet'
        properties: {
          addressPrefix: '10.10.0.0/24'
        }
      }
      {
        name: 'app-subnet'
        properties: {
          addressPrefix: '10.10.1.0/24'
          networkSecurityGroup: {
            id: nsgApp.id
          }
        }
      }
    ]
  }
}

// 2. Network Security Group for App Subnet
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-app-prod'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-AppGW-808'
        properties: {
          priority: 300
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: '10.10.0.0/24'
          destinationAddressPrefix: '10.10.1.0/24'
        }
      }
    ]
  }
}

// 3. Public IP for Application Gateway
resource pipAppGW 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-appgw-prod'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// 4. Application Gateway (v2 SKU)
resource appGateway 'Microsoft.Network/applicationGateways@2023-05-01' = {
  name: 'appgw-${prefix}'
  location: location
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'appgw-subnet')
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: pipAppGW.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'pool-iis-8080'
        properties: {
          backendAddresses: [
            {
              ipAddress: '10.10.1.4'
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-setting-8080'
        properties: {
          port: 8080
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', 'appgw-${prefix}', 'custom-health-probe-8080')
          }
        }
      }
    ]
    probes: [
      {
        name: 'custom-health-probe-8080'
        properties: {
          protocol: 'Http'
          host: '127.0.0.1'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'appgw-${prefix}', 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'appgw-${prefix}', 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule-http-to-backend'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'appgw-${prefix}', 'http-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'appgw-${prefix}', 'pool-iis-8080')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'appgw-${prefix}', 'http-setting-8080')
          }
        }
      }
    ]
  }
}

// 5. Network Interface for Virtual Machine (Private Only)
resource nicVM 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'vm-app-prod-01389'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.10.1.4'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'app-subnet')
          }
        }
      }
    ]
  }
}

// 6. Windows Server 2022 Compute Node
resource vmApp 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'vm-app-prod-01'
  location: location
  zones: [
    '1'
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_F1ads_v5'
    }
    osProfile: {
      computerName: 'vm-app-prod-01'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicVM.id
        }
      ]
    }
  }
}
