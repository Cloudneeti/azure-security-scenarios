$username = "shabuddink@avyanconsulting.com"
$password = "W0l!mullEr1894"
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$subscriptionId = "b4605119-4803-4924-a221-091570e36d01"

### Create the credential object
#$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

#Login-AzureRmAccount -Subscription $subscriptionId -Credential $credential

.\deploy.ps1 -UseCase 10001 -SubscriptionId $subscriptionId -UserName $username -Password $securePassword -UploadBlob -Verbose