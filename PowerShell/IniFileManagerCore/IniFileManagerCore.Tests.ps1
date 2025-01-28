BeforeAll {
    # Import the module
    Import-Module $PSScriptRoot\IniFileManagerCore.psm1 -Force

    # Create a temporary directory for test files
    $script:TestDir = Join-Path $TestDrive 'IniTests'
    New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
}

Describe 'IniFileManagerCore' {
    BeforeEach {
        # Create a fresh test file path for each test
        $script:TestFile = Join-Path $script:TestDir "test_$(New-Guid).ini"
    }

    Context 'Set-IniValue' {
        It 'Creates a new INI file with basic section and key' {
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'Value1'
            
            $content = Get-Content $TestFile -Raw
            $content | Should -Match '\[Test\]'
            $content | Should -Match 'Key1=Value1'
        }

        It 'Adds a new key to existing section' {
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'Value1'
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key2' -Value 'Value2'
            
            $content = Get-Content $TestFile -Raw
            $content | Should -Match 'Key1=Value1'
            $content | Should -Match 'Key2=Value2'
        }

        It 'Updates existing key value' {
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'Value1'
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'UpdatedValue'
            
            $value = Get-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1'
            $value | Should -Be 'UpdatedValue'
        }

        It 'Handles special characters in values' {
            $specialValue = "Value with spaces and symbols: !@#$%^&*()"
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'SpecialKey' -Value $specialValue
            
            $value = Get-IniValue -FilePath $TestFile -Section 'Test' -Key 'SpecialKey'
            $value | Should -Be $specialValue
        }

        It 'Creates nested directory structure if needed' {
            $nestedPath = Join-Path $script:TestDir 'Nested/Deep/Path/test.ini'
            Set-IniValue -FilePath $nestedPath -Section 'Test' -Key 'Key1' -Value 'Value1'
            
            Test-Path $nestedPath | Should -Be $true
        }
    }

    Context 'Get-IniValue' {
        It 'Returns null for non-existent file' {
            $value = Get-IniValue -FilePath 'NonExistentFile.ini' -Section 'Test' -Key 'Key1' -ErrorAction SilentlyContinue
            $value | Should -Be $null
        }

        It 'Returns null for non-existent section' {
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'Value1'
            
            $value = Get-IniValue -FilePath $TestFile -Section 'NonExistentSection' -Key 'Key1'
            $value | Should -Be $null
        }

        It 'Returns null for non-existent key' {
            Set-IniValue -FilePath $TestFile -Section 'Test' -Key 'Key1' -Value 'Value1'
            
            $value = Get-IniValue -FilePath $TestFile -Section 'Test' -Key 'NonExistentKey'
            $value | Should -Be $null
        }

        It 'Retrieves correct value from multiple sections' {
            Set-IniValue -FilePath $TestFile -Section 'Section1' -Key 'Key1' -Value 'Value1'
            Set-IniValue -FilePath $TestFile -Section 'Section2' -Key 'Key1' -Value 'Value2'
            
            $value1 = Get-IniValue -FilePath $TestFile -Section 'Section1' -Key 'Key1'
            $value2 = Get-IniValue -FilePath $TestFile -Section 'Section2' -Key 'Key1'
            
            $value1 | Should -Be 'Value1'
            $value2 | Should -Be 'Value2'
        }
    }

    Context 'File Structure' {
        It 'Preserves multiple sections' {
            Set-IniValue -FilePath $TestFile -Section 'Section1' -Key 'Key1' -Value 'Value1'
            Set-IniValue -FilePath $TestFile -Section 'Section2' -Key 'Key2' -Value 'Value2'
            
            $content = Get-Content $TestFile -Raw
            $content | Should -Match '\[Section1\]'
            $content | Should -Match '\[Section2\]'
            $content | Should -Match 'Key1=Value1'
            $content | Should -Match 'Key2=Value2'
        }

        It 'Maintains file structure when updating values' {
            # Create initial structure
            Set-IniValue -FilePath $TestFile -Section 'Section1' -Key 'Key1' -Value 'Value1'
            Set-IniValue -FilePath $TestFile -Section 'Section2' -Key 'Key2' -Value 'Value2'
            
            # Update a value
            Set-IniValue -FilePath $TestFile -Section 'Section1' -Key 'Key1' -Value 'UpdatedValue'
            
            # Check structure is maintained
            $content = Get-Content $TestFile -Raw
            $content | Should -Match '\[Section1\][\s\S]*\[Section2\]'
            $content | Should -Match 'Key1=UpdatedValue'
            $content | Should -Match 'Key2=Value2'
        }
    }
} 