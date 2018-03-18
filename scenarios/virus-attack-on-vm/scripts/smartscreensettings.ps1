# Requires -Version 3.0

Function Get-SmartScreenSettingsStatus {
[CmdletBinding()]
Param()
Begin {}
Process {
    try {
       $val = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name SmartScreenEnabled -ErrorAction Stop
    } catch {
        
    }
    if ($val) {
        'Smart screen settings is set to: {0}' -f $val.SmartScreenEnabled
    } else {
        'Smart screen settings is set to: Off (by default)'
    }
}
End {}
}

Function Set-SmartScreenSettingsStatus {
[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [ValidateSet("Off","Prompt","RequireAdmin")]
    [system.String]$State
)
Begin {
    # Make sure we run as admin
    $usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $IsAdmin = $usercontext.IsInRole(544)
    if (-not($IsAdmin)) {
        Write-Warning "Must run powerShell as Administrator to perform these actions"
        break
    } 

}
Process {
    try {
        Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name SmartScreenEnabled -ErrorAction Stop -Value $State -Force 
    } catch {
        Write-Warning -Message "Failed to write registry value because $($_.Exception.Message)"
    }
}
End {}
}

Set-SmartScreenSettingsStatus -State Off