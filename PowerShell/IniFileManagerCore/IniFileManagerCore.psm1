class IniSection {
    [string]$Name
    [System.Collections.Specialized.OrderedDictionary]$Values

    IniSection([string]$name) {
        $this.Name = $name
        $this.Values = [System.Collections.Specialized.OrderedDictionary]::new()
    }
}

class IniDocument {
    [System.Collections.Specialized.OrderedDictionary]$Sections

    IniDocument() {
        $this.Sections = [System.Collections.Specialized.OrderedDictionary]::new()
    }

    [void]SetValue([string]$section, [string]$key, [string]$value) {
        if (-not $this.Sections.Contains($section)) {
            $this.Sections[$section] = [IniSection]::new($section)
        }
        $this.Sections[$section].Values[$key] = $value
    }

    [string]GetValue([string]$section, [string]$key) {
        if ($this.Sections.Contains($section) -and $this.Sections[$section].Values.Contains($key)) {
            return $this.Sections[$section].Values[$key]
        }
        return [NullString]::Value
    }

    [void]Load([string]$filePath) {
        if (-not (Test-Path $filePath)) {
            return
        }

        $currentSection = $null
        $reader = [System.IO.StreamReader]::new($filePath)
        
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine().Trim()
                
                # Skip empty lines and comments
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(';')) {
                    continue
                }

                # Check for section
                if ($line.StartsWith('[') -and $line.EndsWith(']')) {
                    $sectionName = $line.Substring(1, $line.Length - 2).Trim()
                    $currentSection = [IniSection]::new($sectionName)
                    $this.Sections[$sectionName] = $currentSection
                    continue
                }

                # Check for key-value pair
                if ($currentSection -and $line.Contains('=')) {
                    $equalPos = $line.IndexOf('=')
                    $key = $line.Substring(0, $equalPos).Trim()
                    $value = $line.Substring($equalPos + 1).Trim()
                    $currentSection.Values[$key] = $value
                }
            }
        }
        finally {
            $reader.Dispose()
        }
    }

    [void]Save([string]$filePath) {
        $writer = [System.IO.StreamWriter]::new($filePath)
        
        try {
            foreach ($section in $this.Sections.Values) {
                # Write section header
                $writer.WriteLine("[$($section.Name)]")
                
                # Write key-value pairs
                foreach ($key in $section.Values.Keys) {
                    $value = $section.Values[$key]
                    $writer.WriteLine("$key=$value")
                }
                
                # Add blank line between sections
                $writer.WriteLine()
            }
        }
        finally {
            $writer.Dispose()
        }
    }
}

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
    
    $ini = [IniDocument]::new()
    
    # Load existing content if file exists
    if (Test-Path $FilePath) {
        $ini.Load($FilePath)
    }
    
    # Set the value
    $ini.SetValue($Section, $Key, $Value)
    
    # Ensure directory exists
    $directory = Split-Path $FilePath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    
    # Save the file
    $ini.Save($FilePath)
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
    
    $ini = [IniDocument]::new()
    $ini.Load($FilePath)
    $value = $ini.GetValue($Section, $Key)
    
    if ($null -eq $value) {
        return $null
    }
    return $value
}

# Export the functions
Export-ModuleMember -Function Set-IniValue, Get-IniValue 