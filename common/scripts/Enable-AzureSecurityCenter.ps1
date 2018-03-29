[CmdletBinding()]
param (

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
    $Password


)

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

    # Enable ASC Policies

    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    Write-Verbose "Checking AzureRM context for Azure security center configuration."
    $currentAzureContext = Get-AzureRmContext
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)

    Write-Verbose "Getting access token for Azure security center."
    Write-Debug ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)
    $token = $token.AccessToken
    $Script:asc_clientId = "1950a258-227b-4e31-a9cf-717495945fc2"              # Well-known client ID for Azure PowerShell
    $Script:asc_redirectUri = "urn:ietf:wg:oauth:2.0:oob"                      # Redirect URI for Azure PowerShell
    $Script:asc_resourceAppIdURI = "https://management.azure.com/"             # Resource URI for REST API
    $Script:asc_url = 'management.azure.com'                                   # Well-known URL endpoint
    $Script:asc_version = "2015-06-01-preview"                                 # Default API Version
    $PolicyName = 'default'
    $asc_APIVersion = "?api-version=$asc_version" #Build version syntax.
    $asc_endpoint = 'policies' #Set endpoint.

    Write-Verbose "Creating authentication header."
    Set-Variable -Name asc_requestHeader -Scope Script -Value @{"Authorization" = "Bearer $token"}
    Set-Variable -Name asc_subscriptionId -Scope Script -Value $currentAzureContext.Subscription.Id

    #Retrieve existing policy and build hashtable
    log "Retrieving data for $PolicyName..."
    $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint/$PolicyName$asc_APIVersion"
    $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
    $a = $asc_request 

    $a