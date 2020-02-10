param(
    [Parameter(mandatory=$true)]
    [string] $vmScaleSetResourceGroupName,

    [Parameter(mandatory=$true)]
    [string] $vmScaleSetName

    [Parameter(mandatory=$false)]
    [string] $frontDoorName,

    [Parameter(mandatory=$false)]
    [string] $frontDoorResourceGroupName
)

Write-Output "Connecting to AzureRunAsConnection"
$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
} catch {
    if (!$servicePrincipalConnection) {
        $errorMessage = "Connection $connectionName not found."
        throw $errorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Write-Output "Gathering VM instances for VM Scale Set $vmScaleSetName"
$vmInstances = $(Get-AzureRmVmssVM -ResourceGroupName $vmScaleSetResourceGroupName -VMScaleSetName $vmScaleSetName)

Write-Output "Reimaging VM instances"
foreach ( $vmInstanceName in $vmInstances ) {

    # Check if there is at least one healthy VM
    while( $($vmInstances).ProvisioningState -NotContains "Succeeded" ) {
        Write-Output "Waiting for a VM to become Succeeded"
        Start-Sleep -Seconds 300  
    }

    # Upgrade the selected InstanceID
    Write-Output "Upgrading $($vmInstanceName.Name)"
    Update-AzureRmVmssInstance -ResourceGroupName $vmScaleSetResourceGroupName -VMScaleSetName $vmScaleSetName -InstanceId "$($vmInstanceName.InstanceID)"

    # Reimage the selected InstanceID
    Write-Output "Reimaging $($vmInstanceName.Name)"
    Set-AzureRmVmssVM -Reimage -ResourceGroupName $vmScaleSetResourceGroupName -VMScaleSetName $vmScaleSetName -InstanceId "$($vmInstanceName.InstanceID)"

    # Take a nap
    Start-Sleep -Seconds 120

}

if ( $frontDoorName -and $frontDoorResourceGroupName ) {
    Write-Output "Purging Front Door Cache"
    Remove-AzFrontDoorContent -ResourceGroupName $frontDoorResourceGroupName -Name $frontDoorName -ContentPath "/*"
}
