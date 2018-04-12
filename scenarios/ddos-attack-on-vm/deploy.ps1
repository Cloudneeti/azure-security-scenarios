<#

Copyright (c) Avyan Consulting Corp. All rights reserved.
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is  furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  FITNESS FOR A PARTICULAR PURPOSE AND ONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#>

[CmdletBinding()]
param (
    # Enter prefix for Resource Groups
    [Parameter(Mandatory = $true)]
    [string]
    $Prefix,

    # Enter Subscription Id for deployment.
    [Parameter(Mandatory = $false)]
    [Alias("subscription")]
    [guid]
    $SubscriptionId,

    # Enter AAD Username with Owner permission at subscription level and Global Administrator at AAD level.
    [Parameter(Mandatory = $false)]
    [Alias("user")]
    [string]
    $UserName,

    # Enter AAD Username password as securestring.
    [Parameter(Mandatory = $false)]
    [Alias("pwd")]
    [securestring]
    $Password,

    # Enter AAD Username password as securestring.
    [Parameter(Mandatory = $false)]
    [string]
    $Location = "East US",

    # Provide artifacts storage account name.
    [Parameter(Mandatory = $false)]
    [string]
    $artifactsStorageAccountName = $null,

    # Provide OMS Workspace Resourcegroup Name.
    [Parameter(Mandatory = $true)]
    [string]
    $omsWorkspaceResourceGroupName,

    # Provide OMS workspace name.
    [Parameter(Mandatory = $true)]
    [string]
    $omsWorkspaceName    
)

$ErrorActionPreference = 'Stop'
Write-Verbose "Setting up deployment variables."
$deploymentName = "ddos-attack-on-vm"
$sessionGuid = New-Guid
$timeStamp = Date -Format dd_yyyy_hh_mm_ss
$rootFolder = Split-Path(Split-Path($PSScriptRoot))
$moduleFolderPath = "$rootFolder\common\modules\powershell\asc.poc.psd1"
$artifactStagingDirectories = @(
    #"$rootFolder\common"
    #"$rootFolder\resources"
)
$workloadResourceGroupName = "{0}-{1}" -f $Prefix, $deploymentName
$commonTemplateParameters = New-Object -TypeName Hashtable # Will be used to pass common parameters to the template.
$artifactsLocation = '_artifactsLocation'
$artifactsLocationSasToken = '_artifactsLocationSasToken'
$storageContainerName = "artifacts"
$actionEmail = "Dummy@azuresecurityscenarious.com"

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
        $credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
        Write-Verbose "Login to Subscription - $SubscriptionId"
        Login-AzureRmAccount -Subscription $SubscriptionId -Credential $credential
    }
}

Write-Verbose "Initialising transcript."
Start-Transcript -Path "$rootFolder\logs\transcript_$timeStamp.txt" -Append -Force

Write-Verbose "Importing custom modules."
Import-Module $moduleFolderPath
Write-Verbose "Module imported."

$deploymentHash = (Get-StringHash $workloadResourceGroupName).substring(0,10)
if ($artifactsStorageAccountName -eq $null) {
    $storageAccountName = 'stage' + $deploymentHash
}
else {
    $storageAccountName = $artifactsStorageAccountName
}
$sessionHash = (Get-StringHash $sessionGuid)
$armDeploymentName = "deploy-$Prefix-$($sessionHash.substring(0,5))"

Write-Verbose "Generating tmp file for deployment parameters."
$tmp = [System.IO.Path]::GetTempFileName()

# Create Resourcegroup
New-AzureRmResourceGroup -Name $workloadResourceGroupName -Location $Location -Force

Write-Verbose "Check if artifacts storage account exists."
$storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})

# Create the storage account if it doesn't already exist
if ($storageAccount -eq $null) {
    Write-Verbose "Artifacts storage account does not exists."
    Write-Verbose "Provisioning artifacts storage account."
    $storageAccount = New-AzureRmStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' `
        -ResourceGroupName $workloadResourceGroupName -Location $Location
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

# Generate the value for artifacts location & 4 hour SAS token for the artifacts location.
$commonTemplateParameters[$artifactsLocation] = $storageAccount.Context.BlobEndPoint + $storageContainerName
$commonTemplateParameters[$artifactsLocationSasToken] = New-AzureStorageContainerSASToken -Container $storageContainerName -Context $storageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)

# Update parameter file with deployment values.
Write-Verbose "Get Parameter file"
$parametersObj = Get-Content -Path "$PSScriptRoot\templates\azuredeploy.parameters.json" | ConvertFrom-Json
Write-Verbose "Updating parameter file."
$parametersObj.parameters.commonReference.value._artifactsLocation = $commonTemplateParameters[$artifactsLocation]
$parametersObj.parameters.commonReference.value._artifactsLocationSasToken = $commonTemplateParameters[$artifactsLocationSasToken]
$parametersObj.parameters.commonReference.value.prefix = $Prefix
$parametersObj.parameters.commonReference.value.omsWorkspace.resourceGroupName = $omsWorkspaceResourceGroupName
$parametersObj.parameters.commonReference.value.omsWorkspace.name = $omsWorkspaceName
( $parametersObj | ConvertTo-Json -Depth 10 ) -replace "\\u0027", "'" | Out-File $tmp

Write-Verbose "Initiate Deployment for TestCase - $Prefix"
New-AzureRmResourceGroupDeployment -ResourceGroupName $workloadResourceGroupName -TemplateFile "$PSScriptRoot\templates\workload\azuredeploy.json" -TemplateParameterFile $tmp -Name $armDeploymentName -Mode Incremental -DeploymentDebugLogLevel All -Verbose -Force

# Getting the deployment output for public IP resource Id
 $deploymentOutputPIP = (Get-AzureRmResourceGroupDeployment -ResourceGroupName $workloadResourceGroupName -Name $armDeploymentName).Outputs.Values.value

 #Getting the resource Id of Public IP
$resourceId = (Get-AzureRmResource -ResourceGroupName $workloadResourceGroupName -ResourceName $test -ResourceType Microsoft.Network/publicIPAddresses).ResourceId

# Configuring the Metrics Alert rule for under DDoS attack status
Add-AzureRmMetricAlertRule -Name "DDoS attack alert" -ResourceGroupName $workloadResourceGroupName -location $Location -TargetResourceId $resourceId -MetricName "IfUnderDDoSAttack" -Operator GreaterThanOrEqual -Threshold 1 -WindowSize 00:05:00 -TimeAggregationOperator Total -Actions $actionEmail -Description "Under DDoS attack alert"