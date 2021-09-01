using module "..\..\Output\Elizium.PoShLog\Elizium.PoShLog.psm1"

Set-StrictMode -Version 1.0

Describe 'PoShLogOptionsManager' -Tag 'plog', 'om' {
  BeforeAll {
    Get-Module Elizium.PoShLog | Remove-Module -Force;
    Import-Module .\Output\Elizium.PoShLog\Elizium.PoShLog.psm1 `
      -ErrorAction 'stop' -DisableNameChecking;

    InModuleScope -ModuleName Elizium.PoShLog {
      [string] $script:ROOT = 'root';
      [string] $script:DIRECTORY = [PoShLogProfile]::DIRECTORY;
    }
  }

  BeforeEach {
    InModuleScope Elizium.PoShLog {
      [scriptblock] $script:ReadRootPath = [scriptblock] {
        [OutputType([string])]
        param()

        return Join-path -Path $TestDrive -ChildPath $ROOT;
      }
      
      [PSCustomObject]$optionsInfo = [PSCustomObject]@{
        Base          = '-changelog.options';
        DirectoryName = $DIRECTORY;
        GroupBy       = 'scope/type/change/break';
        Root          = $ReadRootPath.InvokeReturnAsIs();
      }

      # [PoShLogOptionsManager]
      [object]$script:_manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
    }
  }

  Describe 'FileName' {
    Context 'given: a predefined name' {
      It 'should: return resolved filename' {
        InModuleScope Elizium.PoShLog {
          [boolean]$withEmoji = $true;
          [string]$resolved = $_manager.FileName('Elizium', $withEmoji);
          $resolved | Should -BeExactly 'Elizium-emoji-changelog.options';
        }
      }
    }
  }

  Describe 'FullPath' {
    Context 'given: a predefined name' {
      It 'should: return full path of resolved Emoji filename' {
        InModuleScope Elizium.PoShLog {
          [boolean]$withEmoji = $true;
          [string]$resolved = $_manager.FullPath('Elizium', $withEmoji);
          [string]$directoryPath = Join-Path -Path $TestDrive `
            -ChildPath $ROOT `
            -AdditionalChildPath $DIRECTORY;

          [string]$fullPath = Join-Path -Path $directoryPath `
            -ChildPath 'Elizium-emoji-changelog.options.json';

          $resolved | Should -BeExactly $fullPath;
        }
      }

      It 'should: return full path of resolved filename' {
        InModuleScope Elizium.PoShLog {
          [boolean]$withEmoji = $false;
          [string]$resolved = $_manager.FullPath('Elizium', $withEmoji);
          [string]$directoryPath = Join-Path -Path $TestDrive `
            -ChildPath $ROOT `
            -AdditionalChildPath $DIRECTORY;

          [string]$fullPath = Join-Path -Path $directoryPath `
            -ChildPath 'Elizium-changelog.options.json';

          $resolved | Should -BeExactly $fullPath;
        }
      }
    }
  }

  Describe 'EnsureRepoDirectoryPath' {
    Context 'given: repo options path does not exist' {
      It 'should: create directory' {
        InModuleScope Elizium.PoShLog {
          $_manager.EnsureRepoDirectoryPath();
          [string]$directoryPath = Join-Path -Path $TestDrive `
            -ChildPath $ROOT `
            -AdditionalChildPath $DIRECTORY;

          Test-Path -LiteralPath $directoryPath | Should -BeTrue;
        }
      }
    }
  }

  Describe 'FindOptions' {
    Context 'given: requested name is predefined' {
      Context 'and: does not exist' {
        It 'should: create new and save' {
          InModuleScope Elizium.PoShLog {
            [boolean]$withEmoji = $true;
            [PSCustomObject]$options = $_manager.FindOptions('Elizium', $withEmoji);
            $_manager.Found | Should -BeFalse;
            $options | Should -Not -BeNullOrEmpty;

            [string]$fullPath = $_manager.FullPath('Elizium', $withEmoji);
            Test-Path -LiteralPath $fullPath | Should -BeTrue;
          }
        }
      }
    }
  } # FindOptions

  Describe 'Eject' {
    Context 'given: requested name is predefined' {
      Context 'and: does not exist' {
        It 'should: eject new json config' {
          InModuleScope Elizium.PoShLog {
            [boolean]$withEmoji = $true;
            [PSCustomObject]$options = $_manager.Eject('Elizium', $withEmoji);
            $options | Should -Not -BeNullOrEmpty;

            [string]$fullPath = $_manager.FullPath('Elizium', $withEmoji);
            Test-Path -LiteralPath $fullPath | Should -BeTrue;
          }
        }

        It 'should: set default headings correctly' {
          InModuleScope Elizium.PoShLog {
            [boolean]$withEmoji = $true;
            [string]$placeholder = [PoShLogProfile]::StatementPlaceholder();
            [PSCustomObject]$options = $_manager.Eject('Elizium', $withEmoji);

            3..6 | ForEach-Object {
              [string]$headingType = "H$($_)";
              $options.Output.Headings.$headingType | should -BeExactly $placeholder;
            }
          }
        }
      }
    }

    Context 'given: requested name is predefined' {
      Context 'and: already exists' {
        It 'should: eject new json config and rename previous' {
          InModuleScope Elizium.PoShLog {
            [boolean]$withEmoji = $true;
            [string]$optionsFileName = 'Test-emoji-changelog.options.json';
            [string]$directoryPath = $_manager.EnsureRepoDirectoryPath();
            [string]$destinationPath = $_manager.DirectoryPath($optionsFileName);
            [string]$testPath = "./Tests/Data/changelog/$optionsFileName";
            Copy-Item -LiteralPath $testPath -Destination $destinationPath;

            [PSCustomObject]$options = $_manager.Eject('Test', $withEmoji);
            $options | Should -Not -BeNullOrEmpty;

            [string]$fullPath = $_manager.FullPath('Test', $withEmoji);
            Test-Path -LiteralPath $fullPath | Should -BeTrue;

            [string]$oldOptionsFileName = 'Test-emoji-changelog.options-01.json';
            [string]$oldFullPath = Join-Path -Path $directoryPath -ChildPath $oldOptionsFileName;
            Test-Path -LiteralPath $oldFullPath | Should -BeTrue;

            # Now re-load to check internal representation of options is not persisted
            #
            [PSCustomObject]$options = Get-Content -Path $destinationPath -Raw | ConvertFrom-Json -Depth 20;
            $options.Output.Headings.H3 | Should -Be $([PoShLogProfile]::StatementPlaceholder());
          }
        }
      }
    }
  } # Eject

  Describe 'New-PoShLogOptionsManager' {
    Context 'given: <name> options config' {
      It 'should: create a new PoShLogOptionsManager' -TestCases @(
        @{ Name = 'Test' },
        @{ Name = 'foo' }
      ) {
        InModuleScope Elizium.PoShLog -Parameters @{ Name = $Name; } {
          param(
            [string]$name
          )
          [PSCustomObject]$optionsInfo = [PSCustomObject]@{
            Base          = '-changelog.options';
            DirectoryName = $DIRECTORY;
            GroupBy       = 'scope/type/change/break';
            Root          = $ReadRootPath.InvokeReturnAsIs();
          }
          [Object]$manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
          $manager | Should -Not -BeNullOrEmpty;

          [PSCustomObject]$options = $manager.FindOptions($name, $true);
          $options | Should -Not -BeNullOrEmpty -Because "Failed for '$name'";
        }
      }
    }
  }
} # PoShLogOptionsManager
