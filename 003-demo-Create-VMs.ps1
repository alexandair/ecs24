# DEMO: Provisioning an Azure VM and basic management tasks

<#
You've created a Linux jumpbox VM in the Azure portal.
Region "Create a Linux jumpbox VM" shows how to accomplish the same with a couple of lines of Azure CLI.
The only step that's skipped is a generation of the SSH keys.
We don't need them, because we will authenticate to VM using the Entra ID credentials.
If you've successfully created a Linux VM in the Azure portal, skip that region and go
directly to "Configure Role-Based Access" region
#>

# NOTE: Azure CLI commands should be executed in Azure Cloud Shell unless you've installed Azure CLI locally

#region Define variables

$resourceGroupName = 'ecs24-vms-rg'
$vnetResourceGroupName = 'ecs24-net-rg'
$vnetName = 'demovnet'
$location = 'northeurope'

#endregion

#region Create a Linux jumpbox VM

# Create a resource group for the VMs
New-AzResourceGroup -Name $resourceGroupName -Location $location

# When a VNet and a VM are in the same resource group, you can use --vnet-name $vnetName --subnet jumpbox
# az vm create --image Ubuntu2204 --location $location --name linuxjumpbox --resource-group $resourceGroupName --size Standard_B1ms --vnet-name $vnetName --subnet jumpbox --nsg '""' --output table

# When a VNet and a VM AREN'T in the same resource group, you need to specify a subnet ID
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetResourceGroupName

$jumpboxSubnetId = $vnet.Subnets.id | Where-Object { $_ -match 'jumpbox' } 

az login

# Get a subnet ID with Azure CLI
# az network vnet subnet show --name jumpbox --vnet-name $vnetName --resource-group $vnetResourceGroupName --query id -o tsv

az vm create --image Ubuntu2204 --location $location --name linuxjumpbox --resource-group $resourceGroupName --size Standard_B1ms --subnet $jumpboxSubnetId --nsg '""' --public-ip-sku Standard --generate-ssh-keys --output table 

<#
Install the Entra ID Linux SSH extension. This extension is responsible for the configuration of the Entra ID integration.

There are many security benefits of using Entra ID with SSH certificate-based authentication to log in to Linux VMs in Azure, including:

- Use your Entra ID credentials to log in to Azure Linux VMs.
- Get SSH key based authentication without needing to distribute SSH keys to users or provision SSH public keys on any Azure Linux VMs you deploy. This experience is much simpler than having to worry about sprawl of stale SSH public keys that could cause unauthorized access.
- Reduce reliance on local administrator accounts, credential theft, and weak credentials.
- Password complexity and password lifetime policies configured for Entra ID help secure Linux VMs as well.
- With Azure role-based access control, specify who can login to a VM as a regular user or with administrator privileges. When users join or leave your team, you can update the Azure RBAC policy for the VM to grant access as appropriate. When employees leave your organization and their user account is disabled or removed from Entra ID, they no longer have access to your resources.
- With Conditional Access, configure policies to require multi-factor authentication and/or require client device you are using to SSH be a managed device (for example: compliant device or hybrid Entra ID joined) before you can SSH to Linux VMs.
- Use Azure deploy and audit policies to require Entra ID login for Linux VMs and to flag use of non-approved local accounts on the VMs.
- Login to Linux VMs with Entra ID also works for customers that use Federation Services.
#>

# https://learn.microsoft.com/en-us/entra/identity/devices/howto-vm-sign-in-azure-ad-linux

# Enable System assigned managed identity on the linuxjumpbox VM
az vm identity assign -g $resourceGroupName -n linuxjumpbox

# Install the AADSSHLoginForLinux extension on the linuxjumpbox VM

az vm extension set --publisher Microsoft.Azure.ActiveDirectory --name AADSSHLoginForLinux --resource-group $resourceGroupName --vm-name linuxjumpbox


#endregion

#region Configure Role-Based Access

# Run the following commands in the PowerShell shell in Azure Cloud Shell

$VMID = az vm show --resource-group $resourceGroupName --name linuxjumpbox --query id -o tsv

$EntraIDUser = 'myuser@mydomainname.onmicrosoft.com'

az role assignment create --role "Virtual Machine Administrator Login" --assignee $EntraIDUser --scope $VMID

# Take a note of the public IP address of the Linux jumpbox VM
$publicIP = az vm show -d --resource-group $resourceGroupName  --name linuxjumpbox --query publicIps -o tsv

# Run the following command to add SSH extension for Azure CLI
az extension add --name ssh

az ssh vm --ip $publicIP

# Login to Azure Linux VMs with Entra ID supports exporting the OpenSSH certificate and configuration, allowing you to use any SSH clients that support OpenSSH based certificates to sign in Entra ID.
cd ~/.ssh
az ssh config --file config --ip $publicIP
<#
Generated SSH certificate C:\Users\aleksandar\.ssh\az_ssh_config\52.169.184.195\id_rsa.pub-aadcert.pub is valid until 2024-05-11 08:56:21 PM in local time.
C:\Users\aleksandar\.ssh\az_ssh_config\52.169.184.195 contains sensitive information (id_rsa, id_rsa.pub, id_rsa.pub-aadcert.pub). Please delete it once you no longer need this config file.
#>
cat ~/.ssh/config

ssh $publicIP

#endregion

#region Create a Windows management VM

# Run the following commands in the PowerShell shell in Azure Cloud Shell

# The password length must be between 12 and 123.
# Password must have the 3 of the following: 1 lower case character, 1 upper case character, 1 number and 1 special character.
$cred = Get-Credential azureuser

$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetResourceGroupName

$managementSubnetId = $vnet.Subnets.id.where{$_ -match 'management'} 

az vm create --image Win2022Datacenter --admin-username $cred.UserName --admin-password $cred.GetNetworkCredential().Password --location $location --name windowsmgmt --resource-group $resourceGroupName --size Standard_B1ms --subnet $managementSubnetId --public-ip-address '""' --nsg '""' --output table

# Take a note of the private IP address of the Windows management VM
$privateIP = az vm show -d --resource-group $resourceGroupName  --name windowsmgmt --query privateIps -o tsv
$privateIP

#endregion

#region Establish a RDP connection to Windows management VM thanks to a port forwarding

# Run the following commands in the PowerShell shell LOCALLY

<#
In OpenSSH, local port forwarding is configured using the -L option:

    ssh -L 80:managedvm.example.com:80 jumpboxvm.example.com

This example opens a connection to the jumpboxvm.example.com jump server, 
and forwards any connection to port 80 on the local machine to port 80 on managedvm.example.com.

-N Do not execute a remote command. This is useful for just forwarding ports.
#>
# Thanks to the ~/.ssh/config file, we don't need to specify <yourEntraIDUser>@<publicIPofJumpboxVM>
# ssh -L 3388:<privateIPofTargetVM>:3389 <publicIPofJumpboxVM> -N
# for example:
cd ~/.ssh
az ssh config --file config --ip $publicIP
ssh -L 3388:192.168.2.4:3389 $PublicIP -N

# While the previous command is running, open another PowerShell shell
# Run the following command to RDP to a Windows management VM
mstsc.exe /v:localhost:3388

#endregion

#region Create a Virtual Machine Scale Set

# Our goal is to deploy 2 instances of Windows VMs in a scale set
# and install and configure IIS on them using the Custom Script Extension

# Run the following commands in the PowerShell shell in Azure Cloud Shell

# Define variables

$resourceGroupName = 'ecs24-vms-rg'
$vnetResourceGroupName = 'ecs24-net-rg'
$vnetName = 'demovnet'
$location = 'northeurope'
$cred = Get-Credential azureuser

# Let's get the frontend subnet ID
$vnet = Get-AzVirtualNetwork -Name demovnet -ResourceGroupName $vnetResourceGroupName

$frontendSubnetId = $vnet.Subnets.id | Where-Object { $_ -match 'frontend' } 

<# Unfortunately, the -SubnetName parameter doesn't accept a subnet ID, so we will use Azure CLI again
New-AzVmss `
  -ResourceGroupName $resourceGroupName `
  -VMScaleSetName "demoScaleSet" `
  -Location $location `
  -VirtualNetworkName $vnetName `
  -SubnetName frontend `
  -PublicIpAddressName "demoPublicIPAddress" `
  -LoadBalancerName "demoLoadBalancer" `
  -UpgradePolicyMode "Automatic" `
  -VMSize "Standard_B1ms" `
  -InstanceCount 2 `
  -Credential $cred `
  -ImageName Win2022AzureEditionCore
#>

az vmss create `
--resource-group $resourceGroupName `
--name 'demoScaleSet' `
--location $location `
--subnet $frontendSubnetId `
--public-ip-address 'demoPublicIPAddress' `
--load-balancer 'demoLoadBalancer' `
--storage-sku 'StandardSSD_LRS' `
--upgrade-policy-mode 'Automatic' `
--vm-sku 'Standard_B1ms' `
--instance-count 2 `
--admin-username $cred.UserName `
--admin-password $cred.GetNetworkCredential().Password `
--image Win2022Datacenter

# Azure CLI, by default, doesn't create a load balancing rule to allow access to port 80
# Open the 'demoLoadBalancer' blade in the Azure portal and create the Health probe and Load balancing rule for port 80 

# Configuration parameters for the Custom Script Extension 
  $customConfig = @{
    "fileUris" = (,"https://raw.githubusercontent.com/Azure-Samples/compute-automation-configurations/myuserter/automate-iis.ps1");
    "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File automate-iis.ps1"
  }

code automate-iis.ps1

# Get information about the scale set
$vmss = Get-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName "demoScaleSet"

# Add the Custom Script Extension to install IIS and configure basic website
$vmss = Add-AzVmssExtension `
-VirtualMachineScaleSet $vmss `
-Name "customScript" `
-Publisher "Microsoft.Compute" `
-Type "CustomScriptExtension" `
-TypeHandlerVersion 1.9 `
-Setting $customConfig

# Update the scale set and apply the Custom Script Extension to the VM instances
Update-AzVmss `
-ResourceGroupName $resourceGroupName `
-Name "demoScaleSet" `
-VirtualMachineScaleSet $vmss

# Test the IIS installation
start ("http://{0}" -f (Get-AzPublicIpAddress -Name demoPublicIpAddress -ResourceGroupName $resourceGroupName).IpAddress)


#endregion


#region Deployment with a Bicep file

cd C:\gh\ecs24
code ./main3.bicep

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile ./main3.bicep

Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName

# Test the IIS installation
start ("http://{0}" -f (Get-AzPublicIpAddress -Name vmssnamejpip -ResourceGroupName $resourceGroupName).IpAddress)


#endregion
