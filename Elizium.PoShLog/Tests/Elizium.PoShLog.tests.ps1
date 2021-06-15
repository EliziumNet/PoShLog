using module "../Output/Elizium.PoShLog/Elizium.PoShLog.psm1"

$moduleRoot = Resolve-Path "$PSScriptRoot/..";
$moduleName = Split-Path $moduleRoot -Leaf;

Describe "General project validation: $moduleName" {
  BeforeAll {
    Get-Module Elizium.PoShLog | Remove-Module
    Import-Module ./Output/Elizium.PoShLog/Elizium.PoShLog.psm1 `
      -ErrorAction 'stop' -DisableNameChecking;
  }

  $scripts = Get-ChildItem $moduleRoot -Include *.ps1, *.psm1, *.psd1 -Recurse;

  # TestCases are splatted to the script so we need hashtables
  $testCase = $scripts | Foreach-Object { @{file = $_ } }
  It "Script <file> should be valid powershell" -TestCases $testCase {
    param($file)

    $file.fullName | Should -Exist;

    $contents = Get-Content -Path (Resolve-Path $file.fullName) -ErrorAction Stop;
    $errors = $null;
    $null = [System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors);

    [string]$ignore = '^Unable to find type \[';
    foreach ($e in $errors) {
      if ($e.Message -match $ignore) {
        Write-Host "WARNING (File: '$($file.fullName)'): This could be a bogus error: '$($e.Message)'";
      }
      else {
        Write-Host "ERROR: $($e.Message)";
      }
    }

    $errors = ($errors | Where-Object { $_.Message -notMatch $ignore });
    $errors.Count | Should -Be 0;
  }
}
