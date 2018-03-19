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
    [Parameter(Mandatory = $false)]
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

    [Parameter(Mandatory = $false)]
    [ValidateSet("Deploy","Attack","Remediate")] 
    [string]
    $Command = "Deploy",

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
    $Location = "East US"
)
begin {
    $ErrorActionPreference = 'Stop'
    $moduleFolderPath = "$PSScriptRoot\common\modules\powershell\asc.poc.psd1"
    Import-Module $moduleFolderPath
    $scenarios = Get-Content -Path $PSScriptRoot\azure-security-poc.json | ConvertFrom-Json
    $storageContainerName = "artifacts"
    $artifactsResourceGroupName = 'azuresecuritypoc-artifacts-' + (Get-StringHash $subscriptionId).substring(0,5) + '-rg'
    $deploymentHash = (Get-StringHash $artifactsResourceGroupName).substring(0,10)
    $storageAccountName = 'stage' + $deploymentHash
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

}

process {

    $userInput = $null
    do {
        Write-Host ""
        $userInput = Read-Host -Prompt "Enter scenario name to deploy. Type 'Help' to get the list of scenarios. Type 'Exit' to exit."
        switch ($userInput) {
            'Help' {
                $scenarios.PSObject.Properties | Select-Object -Property Name ,@{Name="Description"; Expression = {$_.value.description}} | Format-Table
            }
            {($scenarios).PSObject.Properties.Name -contains "$_"} {
                $scenario = $_
                $caseNo = ($scenarios | Select-Object -expandproperty $_).caseNo
                if ($SubscriptionId -eq $null) {
                    & "$PSScriptRoot\scenarios\$scenario\deploy.ps1" -CaseNo $caseNo -artifactsStorageAccountName $storageAccountName -Verbose
                }
                else {
                    & "$PSScriptRoot\scenarios\$scenario\deploy.ps1" -CaseNo $caseNo -SubscriptionId $SubscriptionId -UserName $UserName -Password $Password -artifactsStorageAccountName $storageAccountName -Verbose
                }
            }
            'Exit' {
                Write-Host "Exiting.."
                Exit
            }
            Default {Write-Host "Invalid input.Please enter valid POC number." -ForegroundColor Red}
        }
        
    } until ($userInput -eq 'Exit')

}

end {
}