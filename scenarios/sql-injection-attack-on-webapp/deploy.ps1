[CmdletBinding()]
param (
    # Enter prefix for Resource Groups
    [Parameter(Mandatory = $true)]
    [string]
    $Prefix,

    # Enter Subscription Id for deployment.
    [Parameter(Mandatory = $true)]
    [Alias("subscription")]
    [guid]
    $SubscriptionId,

    # Enter AAD Username with Owner permission at subscription level and Global Administrator at AAD level.
    [Parameter(Mandatory = $true)]
    [Alias("user")]
    [string]
    $UserName,

    # Enter AAD Username password as securestring.
    [Parameter(Mandatory = $true)]
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

    [Parameter(Mandatory = $true)]
    [Alias("email")]
    [string]
    $EmailAddressForAlerts

)

$ErrorActionPreference = 'Stop'
Write-Verbose "Setting up deployment variables."
$deploymentName = "sql-injection-attack-on-webapp"
$sessionGuid = New-Guid
$timeStamp = Date -Format dd_yyyy_hh_mm_ss
$rootFolder = Split-Path(Split-Path($PSScriptRoot))
Write-Verbose "Initialising transcript."
Start-Transcript -Path "$rootFolder\logs\transcript_$timeStamp.txt" -Append -Force
$moduleFolderPath = "$rootFolder\common\modules\powershell\asc.poc.psd1"
$workloadResourceGroupName = "{0}-{1}" -f $Prefix, $deploymentName
$commonTemplateParameters = New-Object -TypeName Hashtable # Will be used to pass common parameters to the template.
$artifactsLocation = '_artifactsLocation'
$artifactsLocationSasToken = '_artifactsLocationSasToken'
$storageContainerName = "artifacts"
$aadAppDisplayName = $deploymentName
$parametersObj = Get-Content -Path "$PSScriptRoot\templates\azuredeploy.parameters.json" | ConvertFrom-Json
$aadAppHomepage = "http://$deploymentName"
$aadAppIdentifierUris = $aadAppHomepage
$deploymentPassword = $parametersObj.parameters.commonReference.value.deploymentPassword
$secureDeploymentPassword = $deploymentPassword | ConvertTo-SecureString -AsPlainText -Force
$tenantId = (Get-AzureRmContext).Tenant.TenantId
if ($tenantId -eq $null) {$tenantId = (Get-AzureRmContext).Tenant.Id}
$clientIPAddress = Invoke-RestMethod http://ipinfo.io/json | Select-Object -exp ip
$clientIPHash = (Get-StringHash $clientIPAddress).substring(0, 5)
$databaseName = $parametersObj.parameters.workload.value.sqlServer.databases[0].name
$cmkName = "CMK1" 
$cekName = "CEK1" 
$keyName = "CMK1"
$artifactsStorageAccKeyType = "StorageAccessKey"
$sqlsmodll = (Get-ChildItem "$env:programfiles\WindowsPowerShell\Modules\SqlServer" -Recurse -File -Filter "Microsoft.SqlServer.Smo.dll").FullName
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
        $credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
        Write-Verbose "Login to Subscription - $SubscriptionId"
        Login-AzureRmAccount -Subscription $SubscriptionId -Credential $credential
    }
}
$userPrincipalName = (Get-AzureRmContext).Account.Id

Connect-AzureAD -TenantId $tenantId -Credential $credential

Write-Verbose -Message "Create Azure AD application in Default directory"
if ((Get-AzureADApplication -SearchString $aadAppDisplayName) -eq $null) {
    $aadApplication = New-AzureADApplication -DisplayName $aadAppDisplayName -IdentifierUris $aadAppIdentifierUris
    $aadApplicationClientId = $aadApplication.AppId
    $aadApplicationObjectId = $aadApplication.ObjectId
    New-AzureADApplicationPasswordCredential -ObjectId $aadApplicationObjectId -Value $deploymentPassword
    New-AzureADServicePrincipal -AppId $aadApplicationClientId
    Write-Verbose -Message "Azure Active Directory apps creation successful. AppID is $aadApplicationClientId"
}
else {
    $aadApplication = Get-AzureADApplication -SearchString $aadAppDisplayName
    $aadApplicationClientId = $aadApplication.AppId
    $aadApplicationObjectId = $aadApplication.ObjectId
    New-AzureADApplicationPasswordCredential -ObjectId $aadApplicationObjectId -Value $deploymentPassword
}

Write-Verbose "Importing custom modules."
Import-Module $moduleFolderPath
Write-Verbose "Module imported."

<# Register RPs
$resourceProviders = @(
    "Microsoft.Storage",
    "Microsoft.Compute",
    "Microsoft.KeyVault",
    "Microsoft.Network",
    "Microsoft.Web"
)
if($resourceProviders.length) {
    Write-Host "Registering resource providers"
    foreach($resourceProvider in $resourceProviders) {
        Register-ResourceProviders -ResourceProviderNamespace $resourceProvider
    }
}
#>
$deploymentHash = (Get-StringHash $workloadResourceGroupName).substring(0, 10)
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
    $artifactStagingDirectories = @(
        "$rootFolder\common"
        "$rootFolder\resources"
        "$PSScriptRoot"
    )
    Write-Verbose "Artifacts storage account does not exists."
    Write-Verbose "Provisioning artifacts storage account."
    $storageAccount = New-AzureRmStorageAccount -StorageAccountName $storageAccountName -Type 'Standard_LRS' `
        -ResourceGroupName $workloadResourceGroupName -Location $Location
    Write-Verbose "Artifacts storage account provisioned."
    Write-Verbose "Creating storage container to upload a blobs."
    New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue
}
else {
    $artifactStagingDirectories = @(
        "$PSScriptRoot"
    )
    New-AzureStorageContainer -Name $storageContainerName -Context $storageAccount.Context -ErrorAction SilentlyContinue
}

# Retrieve Access Key 
$artifactsStorageAccKey = (Get-AzureRmResource | Where-Object ResourceName -eq $storageAccountName | Get-AzureRmStorageAccountKey)[0].value 

# Copy files from the local storage staging location to the storage account container
foreach ($artifactStagingDirectory in $artifactStagingDirectories) {
    $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths) {
        Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring((Split-Path($ArtifactStagingDirectory)).length + 1) `
            -Container $storageContainerName -Context $storageAccount.Context -Force
    }
}

# Generate the value for artifacts location & 4 hour SAS token for the artifacts location.
$artifactsLocation = $storageAccount.Context.BlobEndPoint + $storageContainerName
$commonTemplateParameters['_artifactsLocation'] = $artifactsLocation
$artifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $storageContainerName -Context $storageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)
$commonTemplateParameters['_artifactsLocationSasToken'] = $artifactsLocationSasToken

<########### Create Azure Active Directory apps in default directory ###########
Write-Verbose -Message "Create Azure AD application in Default directory"

if ((Get-AzureRmADApplication -IdentifierUri $aadAppIdentifierUris) -eq $null) {
    $aadApplication = New-AzureRmADApplication -DisplayName $aadAppDisplayName -HomePage $aadAppHomepage -IdentifierUris $aadAppIdentifierUris -Password $secureDeploymentPassword
    $aadApplicationClientId = $aadApplication.ApplicationId.Guid
    $aadApplicationObjectId = $aadApplication.ObjectId.Guid
    Write-Verbose -Message "Azure Active Directory apps creation successful. AppID is $aadApplicationClientId"
}
else {
    $aadApplication = Get-AzureRmADApplication -IdentifierUri $aadAppIdentifierUris
    $aadApplicationClientId = $aadApplication.ApplicationId.Guid
    $aadApplicationObjectId = $aadApplication.ObjectId.Guid
}
#>
# Update parameter file with deployment values.
Write-Verbose "Updating parameter file."
$parametersObj.parameters.commonReference.value._artifactsLocation = $commonTemplateParameters['_artifactsLocation']
$parametersObj.parameters.commonReference.value._artifactsLocationSasToken = $commonTemplateParameters['_artifactsLocationSasToken']
$parametersObj.parameters.commonReference.value.prefix = $Prefix
$parametersObj.parameters.workload.value.keyVault.accessPolicies[0].applicationId = $aadApplicationClientId
$parametersObj.parameters.workload.value.keyVault.accessPolicies[0].objectId = $aadApplicationObjectId
$parametersObj.parameters.workload.value.keyVault.accessPolicies[0].tenantId = $tenantId
$parametersObj.parameters.workload.value.sqlServer.sendAlertsTo = $EmailAddressForAlerts
( $parametersObj | ConvertTo-Json -Depth 10 ) -replace "\\u0027", "'" | Out-File $tmp

Write-Verbose "Initiate Deployment for TestCase - $Prefix"
New-AzureRmResourceGroupDeployment -ResourceGroupName $workloadResourceGroupName -TemplateFile "$PSScriptRoot\templates\workload\azuredeploy.json" -TemplateParameterFile $tmp -Name $armDeploymentName -Mode Incremental -DeploymentDebugLogLevel All -Verbose -Force

# Updating SQL server firewall rule
Write-Verbose -Message "Updating SQL server firewall rule."
$allResource = (Get-AzureRmResource | Where-Object ResourceGroupName -EQ $workloadResourceGroupName)
$sqlServerName = ($allResource | Where-Object ResourceType -eq 'Microsoft.Sql/servers').ResourceName

New-AzureRmSqlServerFirewallRule -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -FirewallRuleName "ClientIpRule$clientIPHash" -StartIpAddress $clientIPAddress -EndIpAddress $clientIPAddress -ErrorAction SilentlyContinue
New-AzureRmSqlServerFirewallRule -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -FirewallRuleName "AllowAzureServices" -StartIpAddress 0.0.0.0 -EndIpAddress 0.0.0.0 -ErrorAction SilentlyContinue

Start-Sleep -Seconds 15

# Import SQL bacpac and update azure SQL DB Data masking policy
Write-Verbose -Message "Importing SQL bacpac and Updating Azure SQL DB Data Masking Policy"

# Importing bacpac file
Write-Verbose -Message "Importing SQL backpac from release artifacts storage account."
$sqlBacpacUri = "$artifactsLocation/$deploymentName/artifacts/ContosoPayments.bacpac"
New-AzureRmSqlDatabaseImport -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -DatabaseName $databaseName -StorageKeytype $artifactsStorageAccKeyType -StorageKey $artifactsStorageAccKey -StorageUri "$sqlBacpacUri" -AdministratorLogin 'sqlAdmin' -AdministratorLoginPassword $secureDeploymentPassword -Edition Standard -ServiceObjectiveName S0 -DatabaseMaxSizeBytes 50000 -ErrorAction SilentlyContinue
Start-Sleep -Seconds 100
Write-Verbose -Message "Updating Azure SQL DB Data masking policy on FirstName & LastName Column."
Set-AzureRmSqlDatabaseDataMaskingPolicy -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -DatabaseName $databaseName -DataMaskingState Enabled
Start-Sleep -s 180
New-AzureRmSqlDatabaseDataMaskingRule -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -DatabaseName $databaseName -SchemaName "dbo" -TableName "Customers" -ColumnName "FirstName" -MaskingFunction Default
New-AzureRmSqlDatabaseDataMaskingRule -ResourceGroupName $workloadResourceGroupName -ServerName $sqlServerName -DatabaseName $databaseName -SchemaName "dbo" -TableName "Customers" -ColumnName "LastName" -MaskingFunction Default

# Encrypting Credit card information within database
Write-Verbose "Encrypt SQL DB column Credit card Information"
# Connect to your database.
Add-Type -Path $sqlsmodll
Write-Verbose "Connecting database - $databaseName on $sqlServerName"
$connStr = "Server=tcp:" + $sqlServerName + ".database.windows.net,1433;Initial Catalog=" + "`"" + $databaseName + "`"" + ";Persist Security Info=False;User ID=" + "`"" + "sqladmin" + "`"" + ";Password=`"" + "$deploymentPassword" + "`"" + ";MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
$connection.ConnectionString = $connStr
$connection.Connect()
$server = New-Object Microsoft.SqlServer.Management.Smo.Server($connection)
$database = $server.Databases[$databaseName]

#Granting Users & ServicePrincipal full access on Keyvault
Write-Verbose "Giving Key Vault access permissions to the Users and ServicePrincipal .."
$KeyVaultName = ($allResource | Where-Object ResourceType -eq 'Microsoft.KeyVault/vaults').ResourceName
Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -UserPrincipalName $userPrincipalName -ResourceGroupName $workloadResourceGroupName -PermissionsToKeys all -PermissionsToSecrets all
Write-Verbose "Granted permissions to the users and serviceprincipals."
Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $aadApplicationClientId -ResourceGroupName $workloadResourceGroupName -PermissionsToKeys all -PermissionsToSecrets all

# Creating KeyVault Key to encrypt DB
Write-Verbose "Creating a Keyvault Key"
$key = (Add-AzureKeyVaultKey -VaultName $KeyVaultName -Name $keyName -Destination 'Software').ID

# Switching SQL commands context to the AD Application
Write-Verbose "Creating SQL Column Master Key & Column Encryption Key"
$cmkSettings = New-SqlAzureKeyVaultColumnMasterKeySettings -KeyURL $key
$sqlMasterKey = Get-SqlColumnMasterKey -Name $cmkName -InputObject $database -ErrorAction SilentlyContinue
if ($sqlMasterKey) {Write-Host -ForegroundColor Yellow "SQL Master Key $cmkName already exists."} 
Else {New-SqlColumnMasterKey -Name $cmkName -InputObject $database -ColumnMasterKeySettings $cmkSettings}
Add-SqlAzureAuthenticationContext -ClientID $aadApplicationClientId -Secret $deploymentPassword -Tenant $tenantID
New-SqlColumnEncryptionKey -Name $cekName -InputObject $database -ColumnMasterKey $cmkName

Write-Verbose "SQL encryption has been successfully created. Encrypting SQL Columns"
# Encrypt the selected columns (or re-encrypt, if they are already encrypted using keys/encrypt types, different than the specified keys/types.
$ces = @()
$ces += New-SqlColumnEncryptionSettings -ColumnName "dbo.Customers.CreditCard_Number" -EncryptionType "Deterministic" -EncryptionKey $cekName
$ces += New-SqlColumnEncryptionSettings -ColumnName "dbo.Customers.CreditCard_Code" -EncryptionType "Deterministic" -EncryptionKey $cekName
$ces += New-SqlColumnEncryptionSettings -ColumnName "dbo.Customers.CreditCard_Expiration" -EncryptionType "Deterministic" -EncryptionKey $cekName
Set-SqlColumnEncryption -InputObject $database -ColumnEncryptionSettings $ces
Write-Verbose "Column CreditCard_Number, CreditCard_Code, CreditCard_Expiration have been successfully encrypted"
#>