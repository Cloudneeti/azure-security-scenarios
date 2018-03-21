[CmdletBinding()]
param (
    # Enter prefix for Resource Groups
    [Parameter(Mandatory = $true)]
    [Alias("prefix")]
    [string]
    $Prefix,

    # Enter Subscription Id for deployment.
    [Parameter(Mandatory = $true)]
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

    [switch]
    $UploadBlob


)

begin {
    
    $ErrorActionPreference = 'Stop'
    Write-Verbose "Setting up deployment variables."
    $deploymentName = "virus-attack-on-vm"
    $sessionGuid = New-Guid
    $timeStamp = Date -Format dd_yyyy_hh_mm_ss
    $rootFolder = Split-Path(Split-Path($PSScriptRoot))
    $moduleFolderPath = "$rootFolder\common\modules\powershell\asc.poc.psd1"
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
    $artifactStagingDirectories = @(
        #"$rootFolder\common"
        #"$rootFolder\resources"
        "$PSScriptRoot"
    )
    $workloadResourceGroupName = "{0}-{1}-{2}" -f $Prefix, $deploymentName, 'workload'
    $securityResourceGroupName = "{0}-{1}-{2}" -f $Prefix, $deploymentName, 'security'
    $commonTemplateParameters = New-Object -TypeName Hashtable # Will be used to pass common parameters to the template.
    $artifactsLocation = '_artifactsLocation'
    $artifactsLocationSasToken = '_artifactsLocationSasToken'
    $storageContainerName = "artifacts"

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


}

process {

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

    # Create Resourcegroup
    New-AzureRmResourceGroup -Name $workloadResourceGroupName -Location $Location -Force
    New-AzureRmResourceGroup -Name $securityResourceGroupName -Location $Location -Force

    Write-Verbose "Check if artifacts storage account exists."
    $storageAccount = (Get-AzureRmStorageAccount | Where-Object {$_.StorageAccountName -eq $storageAccountName})

<#
    #Create artifacts storage account
    try {
        $storageAccountName = 'stage' + $deploymentHash
        Write-Verbose "Verify if artifacts stroage acccount already exists."
        $artifactsStorageContext = Get-AzureRmStorageAccount -ResourceGroupName $workloadResourceGroupName -Name $storageAccountName
        Write-Verbose "artifacts storage account found and context retrieved."
    }
    catch {
        Write-Verbose "Creating artifacts storage account."
        $artifactsStorageContext = New-AzureRmStorageAccount -ResourceGroupName $workloadResourceGroupName -Name $storageAccountName `
        -SkuName Standard_LRS -Location $Location -Kind StorageV2 -EnableHttpsTrafficOnly $true
        Write-Verbose "Artifacts storage account created successfully."
    }

    foreach ($directory in $artifactStagingDirectories) {
        Set-DeploymentArtifacts -ResourceGroupName $workloadResourceGroupName `
            -StorageAccountName $artifactsStorageContext.StorageAccountName `
            -DirectoryName $directory
    }
#>
    if ($UploadBlob) {
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
    ( $parametersObj | ConvertTo-Json -Depth 10 ) -replace "\\u0027", "'" | Out-File $tmp

    Write-Verbose "Initiate Deployment for TestCase - $Prefix"
    New-AzureRmResourceGroupDeployment -ResourceGroupName $securityResourceGroupName -TemplateFile "$PSScriptRoot\templates\rg-security\azuredeploy.json" -TemplateParameterFile $tmp -Name $armDeploymentName -Mode Incremental -DeploymentDebugLogLevel All -Verbose -Force

    $deploymentOutput = Get-AzureRmResourceGroupDeployment -ResourceGroupName "$Prefix-virus-attack-on-vm-security" -Name trendmicrodsm
    $parametersObj.parameters.workload.value.virtualMachine.vmWithTdmAgent.publicIPDomainNameLabelTrendDSM = $deploymentOutput.Outputs.trendmicrodsmUri.Value
    ( $parametersObj | ConvertTo-Json -Depth 10 ) -replace "\\u0027", "'" | Out-File $tmp

    Write-Verbose "Initiate Deployment for TestCase - $Prefix"
    New-AzureRmResourceGroupDeployment -ResourceGroupName $workloadResourceGroupName -TemplateFile "$PSScriptRoot\templates\rg-workload\azuredeploy.json" -TemplateParameterFile $tmp -Name $armDeploymentName -Mode Incremental -DeploymentDebugLogLevel All -Verbose -Force

}

end {
}

