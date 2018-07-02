<#
.SYNOPSIS
    Short description
.DESCRIPTION

Copyright (c) Avyan Consulting Corp. All rights reserved.
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is  furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  FITNESS FOR A PARTICULAR PURPOSE AND ONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

.EXAMPLE
    .\deploy-azuresecurityscenarios.ps1 -Help

    Run this command to get list of supported scenarios

.EXAMPLE
    .\deploy-azuresecurityscenarios.ps1 -Scenario "virus-attack-on-vm" -Command Deploy -Verbose

    If you are using Cloud Shell you can simply pass 2 parameters to run the deployment.

.EXAMPLE
    .\deploy-azuresecurityscenarios.ps1 -SubscriptionId <subscriptionId> -UserName <username> -Password <securePassword> -Scenario <scenario> -Command Deploy -Verbose

    If you are running on a local machine pass additional parameters to connect to subscription and run the deployment.

.INPUTS
    Inputs to this cmdlet (if any)
.OUTPUTS
    Output from this cmdlet (if any)
.NOTES
    General notes
.COMPONENT
    The component this cmdlet belongs to
.ROLE
    The role this cmdlet belongs to
.FUNCTIONALITY
    The functionality that best describes this cmdlet
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [Parameter(Mandatory = $false,
        ParameterSetName = "Cleanup"
    )]    
    [ValidateScript( {
            if ( (Get-Content -Path $PSScriptRoot\azure-security-poc.json | ConvertFrom-Json).PSObject.Properties.Name -contains "$_") {
                $true
            }
            else {
                throw "Invalid input. Run deploy-azuresecurityscenarios.ps1 -Help to view supported scenario names."
            }
        })] 
    [string]
    $Scenario,

    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [ValidateSet("Deploy", "Attack", "Mitigate", "Remediate")] 
    [string]
    $Command = "Deploy",

    # Enter Subscription Id for deployment.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [Alias("subscription")]
    [guid]
    $SubscriptionId,

    # Enter AAD Username with Owner permission at subscription level and Global Administrator at AAD level.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [Alias("user")]
    [string]
    $UserName,

    # Enter AAD Username password as securestring.
    [Parameter(Mandatory = $true,
        ParameterSetName = "Deployment"
    )]
    [Alias("pwd")]
    [securestring]
    $Password,

    # Enter AAD Username password as securestring.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [string]
    $Location = "East US",

    # use this switch for help information.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Help"
    )]
    [switch]
    $Help,

    # use this switch for help cleanup deployed resources.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Cleanup"
    )]
    [switch]
    $Cleanup,

    # use this switch to delete common deployed resources.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Cleanup"
    )]
    [switch]
    $DeleteCommonResources,

    # use this switch for help cleanup deployed resources.
    [Parameter(Mandatory = $false,
        ParameterSetName = "AzureSecurityCenter"
    )]
    [switch]
    $ConfigureASC,

    # provide email address for alerts from security center.
    [Parameter(Mandatory = $false,
        ParameterSetName = "AzureSecurityCenter",
        HelpMessage = "Provide email address for recieving alerts from Azure Security Center.")]
    [Alias("email")]
    [string]
    $EmailAddressForAlerts = "dummy@contoso.com",

    # Use this switch to skip OMS deployment
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [switch]
    $SkipOMSDeployment = $false,

    # Use this switch to skip artifacts upload.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Deployment"
    )]
    [switch]
    $SkipArtifactsUpload = $false

)

$ErrorActionPreference = 'Stop'
$scenarios = Get-Content -Path $PSScriptRoot\azure-security-poc.json | ConvertFrom-Json
if ($Help) {
    $scenarios.PSObject.Properties | Select-Object -Property Name , @{Name = "Description"; Expression = {$_.value.description}} | Format-Table
    Break
}
$moduleFolderPath = "$PSScriptRoot\common\modules\powershell\asc.poc.psd1"
Import-Module $moduleFolderPath
$storageContainerName = "artifacts"
$artifactStagingDirectories = @(
    "$PSScriptRoot\common"
    "$PSScriptRoot\resources"
)

# Checking for required modules and importing modules
& "$PSScriptRoot\common\scripts\install-modules.ps1"

if($UserName -eq $null){
    $UserName = (Get-AzureRmContext).Account.Id
}

$commonDeploymentResourceGroupName = "azuresecuritypoc-common-resources"
$tmp = [System.IO.Path]::GetTempFileName()
if ((Get-AzureRmContext).Subscription -eq $null) {
    if ($SubscriptionId -eq $null -or $UserName -eq $null -or $Password -eq $null) {
        throw "Kindly make sure SubscriptionID, Username and Password parameters are provided during the deployment."
    }
    ### Create the credential object
    $credential = New-Object System.Management.Automation.PSCredential($UserName, $Password)
    try {
        Write-Verbose "Setting AzureRM context to Subscription Id - $SubscriptionId."
        Set-AzureRmContext -Subscription $SubscriptionId
    }
    catch {
        Write-Verbose "Login to Subscription - $SubscriptionId"
        Login-AzureRmAccount -Subscription $SubscriptionId -Credential $credential
    }
}
else {
    $subscriptionId = (Get-AzureRmContext).Subscription.Id
}
$deploymentHash = (Get-StringHash $SubscriptionId).substring(0, 10)
$storageAccountName = 'azsecstage' + $deploymentHash
if ($ConfigureASC) {
    Write-Verbose "Enabling Azure Security Center and Policies."
    & "$PSScriptRoot\common\scripts\Configure-AzureSecurityCenter.ps1" -EmailAddressForAlerts $EmailAddressForAlerts -Verbose
    Break
}
$prefix = ($scenarios | Select-Object -expandproperty $Scenario).prefix
if ($Cleanup) {
    Write-Verbose "Intiating Cleanup for $Scenario"
    & "$PSScriptRoot\scenarios\$Scenario\scripts\cleanup.ps1" -Prefix $prefix -Verbose
    Break
}
if ($DeleteCommonResources) {
    try {
        Write-Verbose "Deleting ResourceGroup - $commonDeploymentResourceGroupName"
        Remove-AzureRmResourceGroup -Name $commonDeploymentResourceGroupName -Force
    }
    catch {
        Throw $_
    }
    Write-Host "ResourceGroup - $commonDeploymentResourceGroupName deleted successfully."
}

if ($SkipArtifactsUpload) {
    Write-Verbose "Check if artifacts storage account exists."
    $storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})
    if ($storageAccount -eq $null) {
        Throw "Artifacts storage account does not exists. Please run deployment without SkipArtifactsUpload switch."
    }
    else {
        Write-Verbose "Skipped artifacts upload."
    }
}
else {
    # Create Resourcegroup
    New-AzureRmResourceGroup -Name $commonDeploymentResourceGroupName -Location $Location -Force

    Write-Verbose "Check if artifacts storage account exists."
    $storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})

    # Create the storage account if it doesn't already exist
    if ($storageAccount -eq $null) {
        Write-Verbose "Artifacts storage account does not exists."
        Write-Verbose "Provisioning artifacts storage account."
        $storageAccount = New-AzureRmStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' `
            -ResourceGroupName $commonDeploymentResourceGroupName -Location $Location
        Write-Verbose "Artifacts storage account provisioned."
        Write-Verbose "Creating storage container to upload a blobs."
        New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue *>&1
    }
    else {
        New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue *>&1
    }

    # Copy files from the local storage staging location to the storage account container
    foreach ($artifactStagingDirectory in $artifactStagingDirectories) {
        $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
        foreach ($SourcePath in $ArtifactFilePaths) {
            Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring((Split-Path($ArtifactStagingDirectory)).length + 1) `
                -Container $storageContainerName -Context $storageAccount.Context -Force
        }
    }
}

if ($SkipOMSDeployment) {
    $omsWorkspaceName = (Get-AzureRmResourceGroupDeployment -ResourceGroupName azuresecuritypoc-common-resources | Where-Object DeploymentName -match 'oms').Outputs.workspaceName.Value
    if ($omsWorkspaceName -eq $null) {
        Throw "OMS workspace does not exist. Please run the deployment without SkipOMSDeployment switch"
    }
    else {
        Write-Verbose "Skipped OMS deployment"
    }
}
else {
    Write-Verbose "Generate the value for artifacts location & 1 hour SAS token for the artifacts location."
    $artifactsLocation = $storageAccount.Context.BlobEndPoint + $storageContainerName
    $artifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $storageContainerName -Context $storageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(1)
    Write-Verbose "SAS token for artifacts storage account generated successfully."
    # Update parameter file with deployment values.
    Write-Verbose "Updating parameter file."
    $parametersObj = Get-Content -Path "$PSScriptRoot\scenarios\common-deployments\azuredeploy.parameters.json" | ConvertFrom-Json
    $parametersObj.parameters.commonReference.value._artifactsLocation = $artifactsLocation
    $parametersObj.parameters.commonReference.value._artifactsLocationSasToken = $artifactsLocationSasToken
    ( $parametersObj | ConvertTo-Json -Depth 10 ) -replace "\\u0027", "'" | Out-File $tmp
    
    # Create Resourcegroup
    New-AzureRmResourceGroup -Name $commonDeploymentResourceGroupName -Location $Location -Force
    
    Write-Verbose "Initiate deployment for common resources"
    New-AzureRmResourceGroupDeployment -ResourceGroupName $commonDeploymentResourceGroupName `
        -TemplateFile "$PSScriptRoot\scenarios\common-deployments\azuredeploy.json" `
        -TemplateParameterFile $tmp -Name $commonDeploymentResourceGroupName -Mode Incremental `
        -DeploymentDebugLogLevel All -Verbose -Force
}

$omsWorkspaceResourceGroupName = $commonDeploymentResourceGroupName
$omsWorkspaceName = (Get-AzureRmResourceGroupDeployment -ResourceGroupName azuresecuritypoc-common-resources | Where-Object DeploymentName -match 'oms').Outputs.workspaceName.Value

switch ($Command) {
    "Deploy" { 
        & "$PSScriptRoot\scenarios\$Scenario\deploy.ps1" -Prefix $prefix -artifactsStorageAccountName $storageAccountName -omsWorkspaceResourceGroupName $omsWorkspaceResourceGroupName -omsWorkspaceName $omsWorkspaceName -UserName $UserName -Verbose     
    }
    "Remediate" {

    }
    "Attack" {

    }
}

