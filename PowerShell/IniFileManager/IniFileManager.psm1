# Add the Windows API functions
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public class IniFile
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern int WritePrivateProfileString(
            string lpAppName,
            string lpKeyName,
            string lpString,
            string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetPrivateProfileString(
            string lpAppName,
            string lpKeyName,
            string lpDefault,
            StringBuilder lpReturnedString,
            int nSize,
            string lpFileName);
    }
"@

function Set-IniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Section,
        
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $true)]
        [string]$Value
    )
    
    # Create the file if it doesn't exist
    if (-not (Test-Path $FilePath)) {
        New-Item -Path $FilePath -ItemType File -Force | Out-Null
    }

    # Convert to absolute path as required by the Windows API
    $FilePath = Resolve-Path $FilePath
    
    # Write the value using the Windows API
    $result = [IniFile]::WritePrivateProfileString($Section, $Key, $Value, $FilePath)
    
    if ($result -eq 0) {
        Write-Error "Failed to write to INI file. Error code: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
}

function Get-IniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Section,
        
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return $null
    }

    # Convert to absolute path as required by the Windows API
    $FilePath = Resolve-Path $FilePath
    
    # Create a StringBuilder to store the returned value
    $stringBuilder = New-Object System.Text.StringBuilder(16384)  # 16K characters
    
    # Get the value using the Windows API
    $result = [IniFile]::GetPrivateProfileString($Section, $Key, [NullString]::Value, $stringBuilder, $stringBuilder.Capacity, $FilePath)
    
    if ($result -eq 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        # Error code 203 means "no mapping" which is normal for missing sections/keys
        if ($errorCode -eq 203) {
            return $null
        }
        if ($errorCode -ne 0) {
            Write-Error "Failed to read from INI file. Error code: $errorCode"
            return $null
        }
    }
    
    $value = $stringBuilder.ToString()
    if ([string]::IsNullOrEmpty($value)) {
        return $null
    }
    return $value
}

# Export the functions
Export-ModuleMember -Function Set-IniValue, Get-IniValue 