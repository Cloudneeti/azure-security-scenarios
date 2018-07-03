[CmdletBinding()]
param
(
    
)

# Manage Session Configuration
Set-StrictMode -Version Latest

$rootFolder = Split-Path(Split-Path(Split-Path $MyInvocation.MyCommand.Path)) # this variable refers to Cloudneeti.Deployment folder path

## Required modules 
$requiredModules = @{
    'AzureRM' = '6.2.1';
    'AzureAD' = '2.0.0.131'
}

# Check and Install required modules
Install-RequiredModules -moduleNames $requiredModules
Start-Sleep 30

# Import required modules
$modules = $requiredModules.Keys
try {
    Write-Host "Importing required modules."
    foreach ($module in $modules) {
        $moduleImportStatus = Get-Module -Name $module
        if ($moduleImportStatus -eq $null) {
            Write-Host "Importing - $module."
            Import-Module -Name $module
            Write-Host "Module - $module imported."
        }
    }
}
catch {
    Throw $_
}
