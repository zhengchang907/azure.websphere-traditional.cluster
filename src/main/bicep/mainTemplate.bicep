/*
     Copyright (c) Microsoft Corporation.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

@description('The base URI where artifacts required by this template are located. When the template is deployed using the accompanying scripts, a private location in the subscription will be used and this value will be automatically generated.')
param _artifactsLocation string = deployment().properties.templateLink.uri

@description('The sasToken required to access _artifactsLocation.  When the template is deployed using the accompanying scripts, a sasToken will be automatically generated. Use the defaultValue if the staging location is not secured.')
@secure()
param _artifactsLocationSasToken string = ''

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Boolean value indicating, if user wants to deploy a tWAS cluster for evaluation only.')
param useTrial bool

@description('Username of your IBMid account.')
param ibmUserId string = ''

@description('Password of your IBMid account.')
@secure()
param ibmUserPwd string = ''

@description('Boolean value indicating, if user agrees to IBM contacting my company or organization.')
param shareCompanyName bool = false

@description('Boolean value indicating, if the cluster is a dynamic one or not.')
param dynamic bool = false

@description('The number of VMs to create, with one deployment manager and multiple worker nodes for the remainings.')
param numberOfNodes int

@description('The size of virtual machine to provision for each node of the cluster.')
param vmSize string

@description('The string to prepend to the name of the deployment manager server.')
param dmgrVMPrefix string

@description('The string to prepend to the name of the managed server.')
param managedVMPrefix string

@description('The string to prepend to the DNS label.')
param dnsLabelPrefix string

@description('Username for the Virtual Machine.')
param adminUsername string

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string

@description('Username for WebSphere admin.')
param wasUsername string

@description('Password for WebSphere admin.')
@secure()
param wasPassword string

@description('Boolean value indicating, if an IBM HTTP Server load balancer will be configured.')
param configureIHS bool

@description('The size of virtual machine to provision for each node of the cluster.')
param ihsVmSize string = 'Standard_D2_v3'

@description('The string to prepend to the name of the IBM HTTP Server.')
param ihsVMPrefix string = 'ihs'

@description('The string to prepend to the DNS label of the IBM HTTP Server.')
param ihsDnsLabelPrefix string = 'ihs'

@description('Username for the Virtual Machine of IBM HTTP Server.')
param ihsUnixUsername string = 'ihsadmin'

@description('SSH Key or password for the Virtual Machine of IBM HTTP Server. SSH key is recommended.')
@secure()
param ihsUnixPasswordOrKey string = ''

@description('Type of authentication to use on the Virtual Machine of IBM HTTP Server. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param ihsAuthenticationType string = 'password'

@description('Username for IBM HTTP Server admin.')
param ihsAdminUsername string = 'ihsadmin'

@description('Password for IBM HTTP Server admin.')
@secure()
param ihsAdminPassword string = ''

@description('VNET for cluster.')
param vnetForCluster object = {
  name: 'twascluster-vnet'
  resourceGroup: resourceGroup().name
  addressPrefixes: [
    '10.0.0.32/27'
  ]
  addressPrefix: '10.0.0.32/27'
  newOrExisting: 'new'
  subnets: {
    subnet1: {
      name: 'twascluster-subnet'
      addressPrefix: '10.0.0.32/27'
      startAddress: '10.0.0.36'
    }
  }
}
@description('To mitigate ARM-TTK error: Control Named vnetForCluster must output the newOrExisting property when hideExisting is false')
param newOrExistingVnetForCluster string = 'new'
@description('To mitigate ARM-TTK error: Control Named vnetForCluster must output the resourceGroup property when hideExisting is false')
param vnetRGNameForCluster string = resourceGroup().name

param guidValue string = take(replace(newGuid(), '-', ''), 6)

var const_arguments = format(' {0} {1} {2} {3} {4} {5}', wasUsername, wasPassword, name_dmgrVM, numberOfNodes - 1, dynamic, configureIHS)
var const_dnsLabelPrefix = format('{0}{1}', dnsLabelPrefix, guidValue)
var const_ihsArguments1 = format(' {0} {1} {2} {3} {4}', name_dmgrVM, ihsUnixUsername, ihsAdminUsername, ihsAdminPassword, name_storageAccount)
var const_ihsArguments2 = format(' {0} {1}', name_share, const_mountPointPath)
var const_ihsDnsLabelPrefix = format('{0}{1}', ihsDnsLabelPrefix, guidValue)
var const_ihsLinuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: format('/home/{0}/.ssh/authorized_keys', ihsUnixUsername)
        keyData: ihsUnixPasswordOrKey
      }
    ]
  }
}
var const_linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: format('/home/{0}/.ssh/authorized_keys', adminUsername)
        keyData: adminPasswordOrKey
      }
    ]
  }
}
var const_managedVMPrefix = format('{0}{1}VM', managedVMPrefix, guidValue)
var const_mountPointPath = '/mnt/${name_share}'
var const_newVNet = (newOrExistingVnetForCluster == 'new') ? true : false
var const_scriptLocation = uri(_artifactsLocation, 'scripts/')
var name_dmgrVM = format('{0}{1}VM', dmgrVMPrefix, guidValue)
var name_ihsPublicIPAddress = '${name_ihsVM}-ip'
var name_ihsVM = format('{0}{1}VM', ihsVMPrefix, guidValue)
var name_networkSecurityGroup = '${const_dnsLabelPrefix}-nsg'
var name_publicIPAddress = '${name_dmgrVM}-ip'
var name_share = 'wasshare'
var name_storageAccount = 'storage${guidValue}'
var name_storageAccountPrivateEndpoint = 'storagepe${guidValue}'
var ref_storageAccountPrivateEndpoint = configureIHS ? reference(name_storageAccountPrivateEndpoint, '2021-05-01').customDnsConfigs[0].ipAddresses[0] : ''

// Work around arm-ttk test "Variables Must Be Referenced"
var configBase64 = loadFileAsBase64('config.json')
var config = base64ToJson(configBase64)

module partnerCenterPid './modules/_pids/_empty.bicep' = {
  name: 'pid-fb16aee1-039d-45dc-a476-806224793a6c-partnercenter'
  params: {
  }
}

module shareCompanyNamePid './modules/_pids/_empty.bicep' = if (useTrial && shareCompanyName) {
  name: config.shareCompanyNamePid
  params: {}
}

module clusterStartPid './modules/_pids/_empty.bicep' = {
  name: (useTrial ? config.clusterTrialStart : config.clusterStart)
  params: {
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: name_storageAccount
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource storageAccountPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = if (configureIHS) {
  name: name_storageAccountPrivateEndpoint
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: name_storageAccountPrivateEndpoint
        properties: {
          privateLinkServiceId: resourceId('Microsoft.Storage/storageAccounts/', name_storageAccount)
          groupIds: [
            'file'
          ]
        }
      }
    ]
    subnet: {
      id: const_newVNet ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetForCluster.name, vnetForCluster.subnets.subnet1.name) : existingSubnet.id
    }
  }
  dependsOn: [
    storageAccount
    virtualNetwork
    existingSubnet
  ]
}

resource storageAccountFileSvc 'Microsoft.Storage/storageAccounts/fileServices@2021-09-01' = if (configureIHS) {
  parent: storageAccount
  name: 'default'
}

resource storageAccountFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-09-01' = if (configureIHS) {
  parent: storageAccountFileSvc
  name: name_share
  properties: {
    shareQuota: 1
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-08-01' = if (const_newVNet) {
  name: name_networkSecurityGroup
  location: location
  properties: {
    securityRules: [
      {
        name: 'TCP'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 300
          direction: 'Inbound'
          destinationPortRanges: [
            '9060'
            '9080'
            '9043'
            '9443'
            '80'
          ]
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-08-01' = if (const_newVNet) {
  name: vnetForCluster.name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetForCluster.addressPrefixes
    }
    subnets: [
      {
        name: vnetForCluster.subnets.subnet1.name
        properties: {
          addressPrefix: vnetForCluster.subnets.subnet1.addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource existingVNet 'Microsoft.Network/virtualNetworks@2021-08-01' existing = if (!const_newVNet) {
  name: vnetForCluster.name
  scope: resourceGroup(vnetRGNameForCluster)
}

resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' existing = if (!const_newVNet) {
  parent: existingVNet
  name: vnetForCluster.subnets.subnet1.name
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-08-01' = if (const_newVNet) {
  name: name_publicIPAddress
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: concat(toLower(const_dnsLabelPrefix))
    }
  }
}

resource dmgrVMNetworkInterface 'Microsoft.Network/networkInterfaces@2021-08-01' = if (const_newVNet) {
  name: '${name_dmgrVM}-if'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetForCluster.name, vnetForCluster.subnets.subnet1.name)
          }
        }
      }
    ]
    dnsSettings: {
      internalDnsNameLabel: name_dmgrVM
    }
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource dmgrVMNetworkInterfaceNoPubIp 'Microsoft.Network/networkInterfaces@2021-08-01' = if (!const_newVNet) {
  name: '${name_dmgrVM}-no-pub-ip-if'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: existingSubnet.id
          }
        }
      }
    ]
  }
}

resource managedVMNetworkInterfaces 'Microsoft.Network/networkInterfaces@2021-08-01' = [for i in range(0, (numberOfNodes - 1)): {
  name: '${const_managedVMPrefix}${(i + 1)}-if'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: const_newVNet ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetForCluster.name, vnetForCluster.subnets.subnet1.name) : existingSubnet.id
          }
        }
      }
    ]
    dnsSettings: {
      internalDnsNameLabel: '${const_managedVMPrefix}${(i + 1)}'
    }
  }
  dependsOn: [
    virtualNetwork
    existingSubnet
  ]
}]

resource clusterVMs 'Microsoft.Compute/virtualMachines@2022-03-01' = [for i in range(0, numberOfNodes): {
  name: i == 0 ? name_dmgrVM : '${const_managedVMPrefix}${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: config.imagePublisher
        offer: config.twasNdImageOffer
        sku: config.twasNdImageSku
        version: config.twasNdImageVersion
      }
      osDisk: {
        name: format('{0}-disk', i == 0 ? name_dmgrVM : '${const_managedVMPrefix}${i}')
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: i == 0 ? name_dmgrVM : '${const_managedVMPrefix}${i}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? json('null') : const_linuxConfiguration)
      customData: base64(useTrial ? ' ' : format('{0} {1}', ibmUserId, ibmUserPwd))
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resourceId('Microsoft.Network/networkInterfaces', format('{0}-if', i == 0 ? (const_newVNet ? name_dmgrVM : '${name_dmgrVM}-no-pub-ip') : '${const_managedVMPrefix}${i}'))
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: reference(storageAccount.id, '2021-09-01').primaryEndpoints.blob
      }
    }
  }
  plan: {
    name: config.twasNdImageSku
    publisher: config.imagePublisher
    product: config.twasNdImageOffer
  }
  dependsOn: [
    dmgrVMNetworkInterface
    dmgrVMNetworkInterfaceNoPubIp
    managedVMNetworkInterfaces
  ]
}]

module clusterVMsCreated './modules/_pids/_empty.bicep' = {
  name: 'clusterVMsCreated'
  params: {
  }
  dependsOn: [
    clusterVMs
  ]
}

resource clusterVMsExtension 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = [for i in range(0, numberOfNodes): {
  name: format('{0}/install', i == 0 ? name_dmgrVM : '${const_managedVMPrefix}${i}')
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {
      fileUris: [
        uri(const_scriptLocation, 'install.sh${_artifactsLocationSasToken}')
        uri(const_scriptLocation, 'create-cluster.py${_artifactsLocationSasToken}')
        uri(const_scriptLocation, 'create-dcluster.py${_artifactsLocationSasToken}')
        uri(const_scriptLocation, 'configure-ihs-on-dmgr.sh${_artifactsLocationSasToken}')
        uri(const_scriptLocation, 'configure-im.py${_artifactsLocationSasToken}')
        uri(const_scriptLocation, 'pluginutil.sh${_artifactsLocationSasToken}')
      ]
    }
    protectedSettings: {
      commandToExecute: format('sh install.sh {0}{1}{2}', i == 0, const_arguments, configureIHS ? format(' {0} {1}{2} {3}', name_storageAccount, listKeys(storageAccount.id, '2021-09-01').keys[0].value, const_ihsArguments2, ref_storageAccountPrivateEndpoint) : '')
    }
  }
  dependsOn: [
    storageAccountFileShare
    clusterVMs
  ]
}]

module clusterEndPid './modules/_pids/_empty.bicep' = {
  name: (useTrial ? config.clusterTrialEnd : config.clusterEnd)
  params: {
  }
  dependsOn: [
    clusterVMsExtension
  ]
}

module ihsStartPid './modules/_pids/_empty.bicep' = if (configureIHS) {
  name: (useTrial ? config.ihsTrialStart : config.ihsStart)
  params: {
  }
}

resource ihsPublicIPAddress 'Microsoft.Network/publicIPAddresses@2021-08-01' = if (configureIHS && const_newVNet) {
  name: name_ihsPublicIPAddress
  location: location
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: concat(toLower(const_ihsDnsLabelPrefix))
    }
  }
}

resource ihsVMNetworkInterface 'Microsoft.Network/networkInterfaces@2021-08-01' = if (configureIHS && const_newVNet) {
  name: '${name_ihsVM}-if'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: ihsPublicIPAddress.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetForCluster.name, vnetForCluster.subnets.subnet1.name)
          }
        }
      }
    ]
    dnsSettings: {
      internalDnsNameLabel: name_ihsVM
    }
  }
  dependsOn: [
    virtualNetwork
  ]
}

resource ihsVMNetworkInterfaceNoPubIp 'Microsoft.Network/networkInterfaces@2021-08-01' = if (configureIHS && !const_newVNet) {
  name: '${name_ihsVM}-no-pub-ip-if'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: existingSubnet.id
          }
        }
      }
    ]
  }
}

resource ihsVM 'Microsoft.Compute/virtualMachines@2022-03-01' = if (configureIHS) {
  name: name_ihsVM
  location: location
  properties: {
    hardwareProfile: {
      vmSize: ihsVmSize
    }
    storageProfile: {
      imageReference: {
        publisher: config.imagePublisher
        offer: config.ihsImageOffer
        sku: config.ihsImageSku
        version: config.ihsImageVersion
      }
      osDisk: {
        name: '${name_ihsVM}-disk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: name_ihsVM
      adminUsername: ihsUnixUsername
      adminPassword: ihsUnixPasswordOrKey
      linuxConfiguration: ((ihsAuthenticationType == 'password') ? json('null') : const_ihsLinuxConfiguration)
      customData: base64(useTrial ? ' ' : format('{0} {1}', ibmUserId, ibmUserPwd))
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: const_newVNet ? ihsVMNetworkInterface.id : ihsVMNetworkInterfaceNoPubIp.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: reference(storageAccount.id, '2021-09-01').primaryEndpoints.blob
      }
    }
  }
  plan: {
    name: config.ihsImageSku
    publisher: config.imagePublisher
    product: config.ihsImageOffer
  }
}

module ihsVMCreated './modules/_pids/_empty.bicep' = if (configureIHS) {
  name: 'ihsVMCreated'
  params: {
  }
  dependsOn: [
    ihsVM
  ]
}

resource ihsVMExtension 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = if (configureIHS) {
  parent: ihsVM
  name: 'install'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {
      fileUris: [
        uri(const_scriptLocation, 'configure-ihs.sh${_artifactsLocationSasToken}')
      ]
    }
    protectedSettings: {
      commandToExecute: format('sh configure-ihs.sh{0} {1}{2} {3}', const_ihsArguments1, listKeys(storageAccount.id, '2021-09-01').keys[0].value, const_ihsArguments2, ref_storageAccountPrivateEndpoint)
    }
  }
  dependsOn: [
    storageAccountFileShare
  ]
}

module ihsEndPid './modules/_pids/_empty.bicep' = if (configureIHS) {
  name: (useTrial ? config.ihsTrialEnd : config.ihsEnd)
  params: {
  }
  dependsOn: [
    ihsVMExtension
  ]
}

output resourceGroupName string = resourceGroup().name
output region string = location
output clusterName string = 'MyCluster'
output nodeGroupName string = 'DefaultNodeGroup'
output coreGroupName string = 'DefaultCoreGroup'
output dmgrHostName string = name_dmgrVM
output dmgrPort string = '8879'
output virtualNetworkName string = vnetForCluster.name
output subnetName string = vnetForCluster.subnets.subnet1.name
output adminSecuredConsole string = uri(format('https://{0}:9043/', const_newVNet ? publicIPAddress.properties.dnsSettings.fqdn : reference('${name_dmgrVM}-no-pub-ip-if').ipConfigurations[0].properties.privateIPAddress), 'ibm/console')
output ihsConsole string = configureIHS ? uri(format('http://{0}', const_newVNet ? ihsPublicIPAddress.properties.dnsSettings.fqdn : reference('${name_ihsVM}-no-pub-ip-if').ipConfigurations[0].properties.privateIPAddress), '') : 'N/A'
