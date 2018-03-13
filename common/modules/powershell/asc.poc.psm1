#  Variables

#  Aliases

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

$testCasesCode = [ordered]@{
    "4000"  = @{
        "code" = {  }
        "desc" = ""
    }
    "4001"  = @{
        "code" = {  }
        "desc" = ""
    }
    "4002"  = @{
        "code" = {  }
        "desc" = ""
    }

}


# Export only the functions using PowerShell standard verb-noun naming.
# Be sure to list each exported functions in the FunctionsToExport field of the module manifest file.
# This improves performance of command discovery in PowerShell.
Export-ModuleMember -Function Get-StringHash, Install-RequiredModules, New-RandomPassword
Export-ModuleMember -Variable testCasesCode
