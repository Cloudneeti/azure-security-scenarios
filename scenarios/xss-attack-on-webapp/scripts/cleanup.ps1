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
    $Location = "East US"

)

$ErrorActionPreference = 'Stop'
Write-Verbose "Setting up deployment variables."
$deploymentName = "xss-attack-on-webapp"
$workloadResourceGroupName = "{0}-{1}" -f $Prefix, $deploymentName

try {
    Write-Verbose "Deleting ResourceGroups"
    Remove-AzureRmResourceGroup -Name $workloadResourceGroupName -Force
}
catch {
    Throw $_
}

Write-Host "Resources deleted successfully."