# Custom Configuration
Set-StrictMode -Version Latest

#  Variables

## Default variables

$Error.Clear()

## Custom variables
$rootFolder = Split-Path(Split-Path(Split-Path(Split-Path($PSScriptRoot))))

$testCasesCode = [ordered]@{
    "4000" = @{
        "code" = {  }
        "desc" = ""
    }
    "4001" = @{
        "code" = {  }
        "desc" = ""
    }
    "4002" = @{
        "code" = {  }
        "desc" = ""
    }

}

#  Import required module

#Import-Module AzureRM

#  Functions
<#
.SYNOPSIS
    Converts String into Hash Value.
#>
Function Get-StringHash([String]$String, $HashName = "SHA1") {
    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))| 
        ForEach-Object { [Void]$StringBuilder.Append($_.ToString("x2"))
    }
    $StringBuilder.ToString().Substring(0, 24)
}

<#
.SYNOPSIS
    Function installs required modules for Blueprint.
.EXAMPLE
    PS C:\> $requiredModules=@{'AzureRM' = '4.4.0';'AzureAD' = '2.0.0.131';'SqlServer' = '21.0.17178';'MSOnline' = '1.1.166.0'}
    Hashtable created with required versions and modules.

    PS C:\> Install-RequiredModules -moduleNames $requiredModules
    Missing modules are installed.
#>
function Install-RequiredModules {
    param
    (
        #Modules hashtable
        [Parameter(Mandatory = $true, 
            ValueFromPipelineByPropertyName = $true,
            Position = 0,
            HelpMessage = "Enter modules hashtable")]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $moduleNames
    )
    Process {
        try {
            $modules = $moduleNames.Keys
            foreach ($module in $modules) {
                $requiredModuleVersion = $moduleNames[$module]
                Write-Host "Retrieving version information for module - $module."
                $moduleInformation = Get-InstalledModule $module -RequiredVersion $requiredModuleVersion -ErrorAction SilentlyContinue
                Write-Host "Verifying module status $module."
                if ($moduleInformation -eq $null) {
                    Write-Host "Module - $module not found."
                    Write-Host "Installing module $module with required version - $requiredModuleVersion"
                    Install-Module $module -RequiredVersion $requiredModuleVersion -Force -Scope CurrentUser
                    Write-Host "Module $module installed successfully."
                }
                elseif ($moduleInformation.Version.ToString() -ne $requiredModuleVersion) {
                    Write-Host "Module $module with another version $($moduleInformation.Version.ToString()) found, Installing required module version - $requiredModuleVersion."
                    Install-Module $module -RequiredVersion $requiredModuleVersion -Force -Scope CurrentUser
                    Write-Host "Module - $module with version $requiredModuleVersion installed."
                }
                else {
                    Write-Host "Module - $module with required version - $requiredModuleVersion is installed."
                }
            }
        }
        catch {
            Throw $_
        }
    }
}

<#
.SYNOPSIS
    This function generates a strong 15 length random password using UPPER & lower case alphabets, numbers and special characters.
#>
function New-RandomPassword() {
    ( -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})) + `
    ((10..99) | Get-Random -Count 1) + `
    ('@', '%', '!', '^' | Get-Random -Count 1) + `
    ( -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})) + `
    ((10..99) | Get-Random -Count 1)
}

function Set-DeploymentArtifacts (
    [CmdletBinding()]
    # Parameter help description
    [Parameter(
        Mandatory = $true
    )]
    [string]
    $ResourceGroupName,

    # Parameter help description
    [Parameter(
        Mandatory = $true
    )]
    [string]
    $StorageAccountName,

    # Parameter help description
    [Parameter(
        Mandatory = $true
    )]
    [string]
    $DirectoryName

) {
    try {
        $artifactsContainerName = "artifacts"
        Write-Verbose "Get storage account information."
        $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
        Write-Verbose "Storage account information retrieved successfully."
        $containerList = (Get-AzureStorageContainer -Context $StorageAccount.Context | Select-Object -ExpandProperty Name)
        Write-Verbose "Container list retrieved."
        if ($containerList -eq $null) {
            Write-Verbose "No containers found. Creating container for artifacts."
            New-AzureStorageContainer -Name $artifactsContainerName -Context $storageAccount.Context
            Write-Verbose "Contianer for artifacts created."
        }
        elseif ($artifactsContainerName -notin $containerList) {
            Write-Verbose "Container list retrieved. Container for artifacts was not found."
            New-AzureStorageContainer -Name $artifactsContainerName -Context $storageAccount.Context
            Write-Verbose "Contianer for artifacts created."
        }
        else {
            Write-Host "Container for artifacts already exists."
        }

        Write-Verbose "Scanning Directory $DirectoryName for JSON templates."
        $artifacts = Get-ChildItem $DirectoryName -Recurse -File -Filter *.json
        $artifacts
        Write-Verbose "Uploading templates to artifacts storage account."
        $artifacts | ForEach-Object {
            $_.FullName
            ("$_.FullName").Length
            $_.FullName.Remove(0, ($_.FullName.Length + 1))
            #Set-AzureStorageBlobContent -Context $storageAccount.Context -Container $artifactsContainerName -File $_.FullName -Blob $_.FullName.Remove(0, ($_.FullName.Length + 1)) -Force
            #Write-Verbose "Uploaded $($_.FullName) to $($storageAccount.StorageAccountName)."
        }
    }
    catch {
        $Error
    }
}

<#
.SYNOPSIS
    Registers RPs
#>
Function Register-ResourceProviders {
    Param(
        [string]$ResourceProviderNamespace
    )

    Write-Host "Registering resource provider '$ResourceProviderNamespace'";
    Register-AzureRmResourceProvider -ProviderNamespace $ResourceProviderNamespace;
}

# Export only the functions using PowerShell standard verb-noun naming.
# Be sure to list each exported functions in the FunctionsToExport field of the module manifest file.
# This improves performance of command discovery in PowerShell.
Export-ModuleMember -Function Get-StringHash, Install-RequiredModules, New-RandomPassword, Set-DeploymentArtifacts, Register-ResourceProviders
Export-ModuleMember -Variable testCasesCode, rootFolder
