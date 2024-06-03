
#region Define variables

$resourceGroupName = 'ecs24-vms-rg'
$vmScaleSetName = 'vmssnamej'

#endregion

# Find out the VM Scale Set InstanceIDs
Get-AzVmssVM -ResourceGroupName $resourceGroupName -VMScaleSetName $vmScaleSetName |
Select-Object -ExpandProperty InstanceId -OutVariable InstanceIDs

# windowmgmt VM and VM scale set instances are in the different subnets
# you need to modify a scope for the public profile of Windows Remote Management rule on the target instances
code .\EnableAccessFromWindowsmgmtVM.ps1

Invoke-AzVmssVMRunCommand -ResourceGroupName $resourceGroupName -VMScaleSetName $vmScaleSetName -InstanceId $InstanceIDs[0] -CommandId 'RunPowerShellScript' -ScriptPath 'EnableAccessFromWindowsmgmtVM.ps1'
<# OUTPUT
Value[0]        :
  Code          : ComponentStatus/StdOut/succeeded
  Level         : Info
  DisplayStatus : Provisioning succeeded
  Message       :
Value[1]        :
  Code          : ComponentStatus/StdErr/succeeded
  Level         : Info
  DisplayStatus : Provisioning succeeded
  Message       :
Status          : Succeeded
Capacity        : 0
Count           : 0
#>

Set-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $InstanceIDs[0] -Location "northeurope" -RunCommandName "EnableAccessFromWindowsmgmtVM" -ScriptLocalPath 'c:\gh\ecs24\EnableAccessFromWindowsmgmtVM.ps1'

Get-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $InstanceIDs[0] -RunCommandName "EnableAccessFromWindowsmgmtVM" -Expand InstanceView -ov result
# ";" is added to the end of every line (?!?) even when the line ends with a pipe character "|", breaking the script
$result.Source.Script
$result.instanceview

Set-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $InstanceIDs[0] -Location "northeurope" -RunCommandName "EnableAccessFromWindowsmgmtVM" -ScriptLocalPath 'c:\gh\ecs24\EnableAccessFromWindowsmgmtVM_oneliner.ps1'

Get-AzVMRunCommand -ResourceGroupName $resourceGroupName -VMName $InstanceIDs[0] -RunCommandName "EnableAccessFromWindowsmgmtVM" -Expand InstanceView -ov result
$result.Source.Script
$result.instanceview



 

