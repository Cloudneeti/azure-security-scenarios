<#
.SYNOPSIS
    Short description
.DESCRIPTION
    Long description
.EXAMPLE
    Example of how to use this cmdlet
.EXAMPLE
    Another example of how to use this cmdlet
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
    [ValidateScript({
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
    [ValidateSet("Deploy","Attack","Remediate")] 
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
    [Parameter(Mandatory = $false,
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

    # use this switch for help information.
    [Parameter(Mandatory = $false,
        ParameterSetName = "Cleanup"
    )]
    [switch]
    $Cleanup

)

$ErrorActionPreference = 'Stop'
$scenarios = Get-Content -Path $PSScriptRoot\azure-security-poc.json | ConvertFrom-Json
$prefix = ($scenarios | Select-Object -expandproperty $Scenario).prefix
if ($Help) {
    $scenarios.PSObject.Properties | Select-Object -Property Name ,@{Name="Description"; Expression = {$_.value.description}} | Format-Table
    Break
}
$moduleFolderPath = "$PSScriptRoot\common\modules\powershell\asc.poc.psd1"
Import-Module $moduleFolderPath
$storageContainerName = "artifacts"
$artifactStagingDirectories = @(
    "$PSScriptRoot\common"
    "$PSScriptRoot\resources"
)
if((Get-AzureRmContext).Subscription -eq $null){
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
    $artifactsResourceGroupName = 'azuresecuritypoc-artifacts-' + (Get-StringHash $subscriptionId).substring(0,5) + '-rg'
    $deploymentHash = (Get-StringHash $artifactsResourceGroupName).substring(0,10)
    $storageAccountName = 'stage' + $deploymentHash
}

if ($Cleanup) {
    Write-Verbose "Intiating Cleanup for $Scenario"
    & "$PSScriptRoot\scenarios\$Scenario\scripts\cleanup.ps1" -Prefix $prefix -Verbose
    Break
}

# Create Resourcegroup
New-AzureRmResourceGroup -Name $artifactsResourceGroupName -Location $Location -Force

Write-Verbose "Check if artifacts storage account exists."
$storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})

# Create the storage account if it doesn't already exist
if ($storageAccount -eq $null) {
    Write-Verbose "Artifacts storage account does not exists."
    Write-Verbose "Provisioning artifacts storage account."
    $storageAccount = New-AzureRmStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' `
        -ResourceGroupName $artifactsResourceGroupName -Location $Location
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
#>
& "$PSScriptRoot\scenarios\$Scenario\deploy.ps1" -Prefix $prefix -artifactsStorageAccountName $storageAccountName -Verbose