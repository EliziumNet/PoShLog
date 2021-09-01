using module "..\..\Output\Elizium.PoShLog\Elizium.PoShLog.psm1"

Set-StrictMode -Version 1.0

Describe 'PoShLog' -Tag 'plog' {
  BeforeAll {
    Get-Module Elizium.PoShLog | Remove-Module -Force;
    Import-Module .\Output\Elizium.PoShLog\Elizium.PoShLog.psm1 `
      -ErrorAction 'stop' -DisableNameChecking;

    InModuleScope -ModuleName Elizium.PoShLog {
      # The order of these regex matter, the most restrictive should come first.
      # They should contain the following named group reference definitions:
      #
      # * <type> -> mandatory
      # * <scope> -> optional
      # * <issue> -> optional
      #
      # It is highly recommended that the groups marked optional are present in the expressions
      # to get the best out of the tool. However, if running against a repo with low quality
      # commit messages, it may be necessary to define regex(s) that don't contain these fields.
      #
      [string[]]$script:_includes = @(
        # feat(foo)!: Add new bar (#42)
        #
        $(
          '^(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '(?:\((?<scope>[\w]+)\))?(?<break>!)?:\s(?<body>[\w\W\s]+)(?:\(#(?<issue>\d{1,6})\))'
        )

        # feat(foo)!: #42 Add new bar
        #
        $(
          '^(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '(?:\((?<scope>[\w]+)\))?(?<break>!)?:\s(?:#(?<issue>\d{1,6}))(?<body>[\w\W\s]+)'
        ),

        # (feat #42)!: Add new bar
        #
        $(
          '^\(?(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '\s+(?:#(?<issue>\d{1,6}))?\)?(?<break>!)?:\s(?<body>[\w\W\s]+)'
        )
      )

      [string[]]$script:_excludes = @();
      [string]$script:delim = "`t";

      [array]$script:_feed = @( # from..until 
        # 3.0.2..HEAD (unreleased)
        #
        $("2021-04-19 18:20:49 +01:00$($delim)9cadab32fd3feb3996ca933ddd2a751ae28e641a$($delim)plastikfan$($delim)fix(foo): #999 Merge branch 'release/3.0.2'"),

        # 3.0.1..3.0.2
        #
        $("2021-04-19 18:17:15 +01:00$($delim)7bd92c2e3476687311e9cb0e75218ace1a7ef5ce$($delim)plastikfan$($delim)Bump version to 3.0.2"),
        $("2021-04-19 17:10:14 +01:00$($delim)23e25cbff58be51c173bb807f49fed78ad289cdf$($delim)plastikfan$($delim)fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux"),

        # 3.0.0..3.0.1
        #
        $("2021-04-19 16:17:04 +01:00$($delim)dc800c68e4aaa6be692c8254490945ad73f69e6d$($delim)plastikfan$($delim)feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline"),
        $("2021-04-19 16:23:44 +01:00$($delim)b2eef128d0ebc3b9775675a3b6481f0eb41a79e6$($delim)plastikfan$($delim)Merge branch 'feature/change-command-pipeline-invocation'"),
        $("2021-04-19 13:25:29 +01:00$($delim)283093511fb2f67b4026e6b319b87acf5b2eac49$($delim)plastikfan$($delim)chore(pstools): #147 get-CommandDetail is now an internal function"),

        # 2.0.0..3.0.0
        #
        $("2021-04-15 13:24:57 +01:00$($delim)d227403012774896857387d9f11e7d35d36b703b$($delim)plastikfan$($delim)(doc #127): Minor docn tweaks"),
        $("2021-04-15 09:53:47 +01:00$($delim)b4bdc4b507f50e3a0a953ce2f167415f4fff78a0$($delim)plastikfan$($delim)(doc #127): Fix links in markdown"),
        $("2021-04-15 16:57:41 +01:00$($delim)b0c917486bc71056622d22bc763abcf7687db4d5$($delim)plastikfan$($delim)(fix #64)!: Add Trigger count to Summary"),
        $("2021-04-15 12:09:19 +01:00$($delim)b055f0b43d1c0518b36b9fa48d23baeac03e55e2$($delim)plastikfan$($delim)(doc #127): Add boostrap docn"),
        $("2021-04-15 09:21:51 +01:00$($delim)31277e6725a753a20d80d3504615fbdb16344a22$($delim)plastikfan$($delim)(doc #127): Add docn for Test-IsAlreadyAnchoredAt"),

        # 1.2.0..2.0.0
        #
        $("2021-01-15 08:57:53 +00:00$($delim)fe2db959f9b1e8fd902b080b44a5508adeebaeb9$($delim)plastikfan$($delim)(fix #98):Select-Patterns; When no filter supplied and LOOPZ_GREPS_FILTER not defined, default to ./*.*"),
        $("2021-01-15 08:59:36 +00:00$($delim)8e04f6c75325ddd7cb66303f71501ec26aac07ae$($delim)plastikfan$($delim)feature/fix-select-text-env-var-not-def"),
        $("2021-01-14 20:20:02 +00:00$($delim)54db603182807ef213b111519fd05b547cc5ea1e$($delim)plastikfan$($delim)(fix #98): Rename Select-Text to Select-Patterns"),
        $("2021-01-14 19:52:13 +00:00$($delim)193df3a22c60fe1d6a06b2cf9771968bbf0b0490$($delim)plastikfan$($delim)(doc #89): fix typos in README"),

        # 1.1.1..1.2.0
        #
        $("2020-09-03 13:45:41 +01:00$($delim)e280dea7daea7ae99f7517c876f05ef138538e02$($delim)plastikfan$($delim)(fix #34): Make tests platform friendly (break on first item)"),
        $("2020-09-16 22:49:55 +01:00$($delim)ab3a9579019b7800c06e95f5af7e3683b321de9c$($delim)plastikfan$($delim)(fix #36): Add controller tests"),
        $("2020-09-17 11:29:13 +01:00$($delim)7e3c5d36e0bc83bdfbab4f2f8563468fcd88aa9c$($delim)plastikfan$($delim)(fix #36): Minor controller/test improvements"),
        $("2020-09-16 15:11:29 +01:00$($delim)5130be22558649f5a7ba69689d7416a29b288d40$($delim)plastikfan$($delim)(fix #36): Fix New-Controller parameter sets"),
        $("2020-09-03 12:50:33 +01:00$($delim)22287029a3a86f1f2c9cd73433075ec8a1d543f3$($delim)plastikfan$($delim)(fix #34)!: Fix Tests broken on mac"),

        # 1.1.0..1.1.1
        #
        $("2020-08-31 11:50:59 +01:00$($delim)fac0998be058cc00398066b333516c9aea4c61c4$($delim)plastikfan$($delim)(fix #35): Catch the MethodInvocationException"),
        $("2020-08-29 16:35:01 +01:00$($delim)379aefde5a2cd10dcc6d19e2e07691e9d8c74c80$($delim)plastikfan$($delim)(fix: #34): Use WhatIf appropriately (not on directory creation)"),
        $("2020-08-29 10:01:25 +01:00$($delim)15eeb4c2098060afb68e28bf04dd88c5dbc19366$($delim)plastikfan$($delim)(fix: #33): remove incorrect parameter validation on FuncteeParams"),
        $("2020-09-02 16:37:01 +01:00$($delim)124ae0e81d4e8af762a986c24d0f8c2609f3b694$($delim)plastikfan$($delim)fix Analyse task"),
        $("2020-08-29 16:36:27 +01:00$($delim)06d055c6a79062439596c42ecf63a0f5ee42ee8d$($delim)plastikfan$($delim)Merge branch 'feature/fix-mirror-whatif"),

        # 1.0.1..1.1.0
        #
        $("2020-08-21 14:19:37 +01:00$($delim)fa8aea14a6b63ddd4d9c08f8f0a00edbcf9d116f$($delim)plastikfan$($delim)Merge branch 'feature/fix-utility-globals"),
        $("2020-08-21 16:30:25 +01:00$($delim)abc321c70f16627d1f657cbdee99de89f21c27c8$($delim)plastikfan$($delim)rename edit-RemoveSingleSubString.tests.ps1"),
        $("2020-08-21 14:08:07 +01:00$($delim)a055776bebc1c1fa7a329f7df6c6d946c17431f4$($delim)plastikfan$($delim)(feat #24): dont add files to FunctionsToExport if they are not of the form verb-noun"),
        $("2020-08-21 19:13:17 +01:00$($delim)5e2b4279b0775cfa1fbf9032691ca910ed4c7979$($delim)plastikfan$($delim)(feat #24): Export functions and variables properly via psm"),

        # 1.0.0..1.0.1
        #
        $("2020-08-17 13:59:08 +01:00$($delim)3884bbec11f622f0c5ea8474049a891c02e0eb09$($delim)plastikfan$($delim)(feat #20): Rm ITEM-VALUE/PROPERTIES; use Pairs instead; Partial check"),
        $("2020-08-18 15:14:21 +01:00$($delim)11120d3c4ec110123417fcb36423403486d02275$($delim)plastikfan$($delim)Bump version to 1.0.1")
      );

      [scriptblock]$script:_noTagsInRepo = [scriptblock] { # ReadLogTags
        return @();
      }
    }
  }

  BeforeEach {
    # NB: test data taken from Loopz as there are more commits there to work from
    #
    InModuleScope Elizium.PoShLog {

      class TagData {
        [DateTime]$DAT;
        [string]$TimeStamp;
        [string]$Label;

        TagData([string]$label, [string]$timestamp) {
          $this.Label = $label;
          $this.TimeStamp = $timestamp;
          $this.DAT = [DateTime]::Parse($timestamp);
        }
      }

      [TagData]$script:_headTagData = [TagData]::new('HEAD', '2021-04-19 18:20:49 +0100');

      [hashtable]$script:_tags = @{
        '3.0.2' = [TagData]::new('3.0.2', '2021-04-19 18:17:15 +0100');
        '3.0.1' = [TagData]::new('3.0.1', '2021-04-19 16:32:22 +0100');
        '3.0.0' = [TagData]::new('3.0.0', '2021-04-15 19:30:42 +0100');
        '2.0.0' = [TagData]::new('2.0.0', '2021-01-18 16:06:43 +0000');
        '1.2.0' = [TagData]::new('1.2.0', '2020-09-17 20:07:59 +0100');
        '1.1.1' = [TagData]::new('1.1.1', '2020-09-02 16:40:04 +0100');
        '1.1.0' = [TagData]::new('1.1.0', '2020-08-21 19:20:22 +0100');
        '1.0.1' = [TagData]::new('1.0.1', '2020-08-18 15:14:21 +0100');
        '1.0.0' = [TagData]::new('1.0.0', '2020-08-18 14:44:59 +0100');
      }

      [hashtable]$script:_overrides = @{
        'ReadHeadDate' = [scriptblock] {
          return $_headTagData.TimeStamp;
        }

        'ReadLogTags'  = [scriptblock] {

          [array]$result = $_tags.PSBase.Keys | Sort-Object -Descending | ForEach-Object {
            [string]$timestamp = $_tags[$_].TimeStamp;

            "$($timestamp)  (tag: $_)"; # eg: '2021-04-19 18:20:49 +0100  (tag: HEAD)'
          }

          return $result;
        }

        'ReadLogRange' = [scriptblock] {
          param(
            [Parameter()]
            [string]$range,

            [Parameter()]
            [string]$format
          )
          [regex]$rangeRegex = [regex]::new('^(?:(?<from>\d\.\d\.\d)\.{2})?(?<until>\d\.\d\.\d|HEAD)$');
          [regex]$dateTimeRegex = [regex]::new('^(?<date>\d{4}-\d{2}-\d{2}) (?<time>\d{2}:\d{2}:\d{2})\s(?:\+\d{2}:\d{2})?');

          [array]$result = if ($rangeRegex.IsMatch($range)) {
            [System.Text.RegularExpressions.Match]$mRg = $rangeRegex.Match($range)?[0];
            [System.Text.RegularExpressions.GroupCollection]$groupsRg = $mRg.Groups;

            $_feed | Where-Object {
              [System.Text.RegularExpressions.Match]$mDt = $dateTimeRegex.Match($_)?[0];
              [System.Text.RegularExpressions.GroupCollection]$groupsDt = $mDt.Groups;

              [DateTime]$commitDate = [DateTime]::Parse($groupsDt['0'].Value);

              if ($groupsRg['from'].Success -and $groupsRg['until'].Success) {
                [DateTime]$fromDate = $_tags[$($groupsRg['from'].Value)].DAT;
                [DateTime]$untilDate = $groupsRg['until'].Value -eq 'HEAD' ? `
                  $_headTagData.DAT : $_tags[$($groupsRg['until'].Value)].DAT;

                ($commitDate.Ticks -gt $fromDate.Ticks) -and ($commitDate.Ticks -le $untilDate.Ticks);
              }
              elseif ($groupsRg['until'].Success) {
                [DateTime]$untilDate = $groupsRg['until'].Value -eq 'HEAD' ? `
                  $_headTagData.DAT : $_tags[$($groupsRg['until'].Value)].DAT;
                ($commitDate.Ticks -le $untilDate.Ticks);
              }
              else {
                $false;
              }
            }
          }
          else {
            @();
          }

          return $result;
        }

        'ReadRemote'   = [scriptblock] {
          return 'https://github.com/EliziumNet/PoShLog';
        }
      }

      
      # The options object should be persisted to the current directory. The user
      # should run in the repo root
      #
      # Symbol references:
      # {symbol}: static symbol name or variable
      # {_X}: lookup value in 'Output' hash
      #
      [PSCustomObject]$script:_options = [PSCustomObject]@{
        PSTypeName    = 'PoShLog.Options';
        #
        Snippet       = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Snippet';
          #
          Prefix     = [PSCustomObject]@{
            PSTypeName    = 'PoShLog.Options.Snippet.Prefix';
            #
            Conditional   = '?'; # breakStmt
            Literal       = '!'; # Anything in Output.Literals
            Lookup        = '&'; # Anything inside Output.Lookup
            NamedGroupRef = '^'; # Any named group ref inside include regex(s)
            Statement     = '*'; # Output.Statements
            Variable      = '+'; # (type, scope, change, link, tag, date, avatar) (resolved internally)
          }
        }
        Selection     = [PSCustomObject]@{
          PSTypeName          = 'PoShLog.Options.Selection';
          #
          Order               = 'desc';
          SquashBy            = '#(?<issue>\d{1,6})'; # optional field
          Last                = $true;
          IncludeMissingIssue = $true;
          Subject             = [PSCustomObject]@{
            PSTypeName = 'PoShLog.Options.Selection.Subject';
            #
            Include    = $_includes;
            Exclude    = $_excludes;
            Change     = '^[\w]+'; # only applied if the matching include not include 'change' named group
          }
          Tags                = [PSCustomObject]@{
            PSTypeName = 'PoShLog.Options.Selection.Tags';
            # FROM, commits that come after the TAG
            # UNTIL, commits up to and including TAG
            #
            # In these tests, there is no default, however, when we generate
            # the default config, the default here will be Until = 'HEAD',
            # which means get everything
            #
          }
        }
        SourceControl = [PSCustomObject]@{
          PSTypeName   = 'PoShLog.Options.SourceControl';
          #
          Name         = 'GitHub';
          HostUrl      = 'https://github.com/';
          AvatarSize   = '24';
          CommitIdSize = 7;
        }
        Output        = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Output';
          #
          # special variables:
          # -> &{_A} = change => indexes into the Authors hash
          # -> &{_B} = change => indexes into the Breaking hash
          # -> &{_C} = change => indexes into the Change hash
          # -> &{_S} = scope => indexes into the Scopes hash if defined
          # -> &{_T} = type => indexes into the Types hash
          #
          Headings   = [PSCustomObject]@{ # document headings
            PSTypeName = 'PoShLog.Options.Output.Headings';
            #
            H2         = 'Release [+{display-tag}] / +{date}';
            H3         = '*{$}'; # *{$} is translated into the correct statement from groupBy
            H4         = '*{$}';
            H5         = '*{$}';
            H6         = '*{$}';
            Dirty      = 'DIRTY: *{dirtyStmt}';
          }

          Sections   = [PSCustomObject]@{
            Release = [PSCustomObject]@{
              Highlights       = "*{highlightsStmt}";
              HighlightContent = @('', '*{highlightDummyStmt}');
            }
          }

          # => /#change-log/##release/###scope/####type
          # /#change-log/##release/ is fixed and can't be customised
          #
          # valid GroupBy legs are: scope/type/change/breaking, which can be specified in
          # any order. Only the first 4 map to headings H3, H4, H5 and H6
          #
          GroupBy    = 'scope/type/break/change';

          LookUp     = [PSCustomObject]@{ # => '&'
            PSTypeName     = 'PoShLog.Options.Output.Lookup';
            #
            # => &{_A} ('_A' is a synonym of 'author')
            #
            Authors        = @{
              'plastikfan' = ':bird:';
              '?'          = ':woman_office_worker:';
            }
            # => &{_B} ('_B' is a synonym of 'break')
            # In the regex, breaking change is indicated by ! (in accordance with
            # established wisdom) and this is translated into 'breaking', and if
            # missing, 'non-breaking', hence the following loop up keys.
            #
            BreakingStatus = @{
              'breaking'     = ':warning: BREAKING CHANGES';
              'non-breaking' = ':recycle: NON BREAKING CHANGES';
            }
            # => &{_C} ('_C' is a synonym of 'change')
            #
            ChangeTypes    = @{ # The first word in the commit subject after 'type(scope): '
              'Add'       = ':heavy_plus_sign:';
              'Change'    = ':copyright:';
              'Fixed'     = ':beetle:';
              'Deprecate' = ':heavy_multiplication_x:'
              'Remove'    = ':heavy_minus_sign:';
              'Secure'    = ':key:';
              'Update'    = ':copyright:';
              '?'         = ':lock:';
            }
            # => &{_S} ('_S' is a synonym of 'scope')
            #
            Scopes         = @{
              # this is user defined. It should be maintained. Known scopes in
              # the project should be defined here
              #
              'all'     = ':star:';
              'pstools' = ':parking:';
              'remy'    = ':registered:';
              'signals' = ':triangular_flag_on_post:';
              'foo'     = ':alien:';
              'bar'     = ':space_invader:';
              'baz'     = ':bomb:';
              '?'       = ':lock:';
            }
            # => &{_T} ('_T' is a synonym of 'type')
            # (These types must be consistent with includes regex)
            #
            Types          = @{
              'fix'   = ':sparkles:';
              'feat'  = ':gift:';
              'build' = ':hammer:';
              'chore' = ':nut_and_bolt:';
              'ci'    = ':trophy:';
              'doc'   = ':clipboard:';
              'docs'  = ':clipboard:';
              'style' = ':hotsprings:';
              'ref'   = ':gem:';
              'perf'  = ':rocket:';
              'test'  = ':test_tube:';
              '?'     = ':lock:';
            }
          }
          Literals   = [PSCustomObject]@{ # => '!'
            PSTypeName    = 'PoShLog.Options.Output.Literals';
            #
            Broken        = ':warning:';
            NotBroken     = ':recycle:';
            BucketEnd     = '---';
            DateFormat    = 'yyyy-MM-dd';
            Dirty         = ':poop:';
            Uncategorised = 'uncategorised';
          }
          Statements = [PSCustomObject]@{ # => '*'
            PSTypeName     = 'PoShLog.Options.Output.Statements';
            #
            ActiveScope    = "+{scope}";
            Author         = ' by `@+{author}` &{_A}'; # &{_A}: Author, +{avatar}: git-avatar
            Avatar         = ' by `@+{author}` +{avatar-img}';
            Break          = '!{broken} *BREAKING CHANGE* ';
            Breaking       = '&{_B}';
            Change         = '[Change Type: &{_C}+{change}] => ';
            IssueLink      = ' \<+{issue-link}\>';
            Highlights     = ":sparkles: HIGHLIGHTS";
            HighlightDummy = "+ Lorem ipsum dolor sit amet";
            Meta           = ' (Id: +{commitid-link})?{issue-link;issueLinkStmt}'; # issue-link must be conditional
            Commit         = '+ ?{is-breaking;breakStmt}?{is-squashed;squashedStmt}*{changeStmt}*{subjectStmt}*{avatarStmt}*{metaStmt}';
            DirtyCommit    = "+ ?{is-breaking;breakingStmt}+{subject}";
            Dirty          = '!{dirty}';
            Scope          = 'Scope(&{_S}?{scope;activeScopeStmt;Uncategorised})';
            Squashed       = 'SQUASHED: ';
            Subject        = 'Subject: **+{subject}**';
            Type           = 'Commit-Type(&{_T} +{type})';
            Ungrouped      = "UNGROUPED!";
          }
          Warnings   = [PSCustomObject]@{
            PSTypeName = 'PoShLog.Options.Output.Warnings';
            Disable    = @{
              'MD253' = 'line-length';
              'MD024' = 'no-duplicate-heading/no-duplicate-header';
              'MD026' = 'no-trailing-punctuation';
              'MD033' = 'no-inline-html';
            }
          }

          Template   = $(Get-Content -Path './Tests/Data/changelog/TEMPLATE.md' -Raw);
        }
      } # $_options

      [PSCustomObject]$script:_head = [PSCustomObject]@{
        PSTypeName = 'PoShLog.TagInfo';
        Label      = 'HEAD';
        Date       = [DateTime]::Parse('2021-04-19 18:20:49 +0100');
      }

      function script:New-TestChangeLog {
        param(
          [Parameter()]
          [PSCustomObject]$Options,

          [Parameter()]
          [hashtable]$Overrides
        )
        # [ProxyGit]
        [object]$proxy = New-ProxyGit -Overrides $Overrides;

        [object]$git = [Git]::new($Options, $proxy);
        [GroupByImpl]$grouper = [GroupByImpl]::new($Options);
        [MarkdownPoShLogGenerator]$generator = [MarkdownPoShLogGenerator]::new(
          $Options, $git, $grouper
        );
        [object]$changeLog = [PoShLog]::new($Options, $git, $grouper, $generator);

        [PSCustomObject]$dependencies = [PSCustomObject]@{
          PSTypeName    = 'PoShLog.Test.Dependencies'
          #
          SourceControl = $git;
          Grouper       = $grouper;
          Generator     = $generator;
        }

        return $changeLog, $dependencies;
      }

      [object]$script:_changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;

      function script:Show-Releases {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
        param(
          [hashtable]$Releases,
          [object]$changer
        )

        [int]$squashedCount = 0;
        [int]$commitsCount = 0;

        Write-Host "===> found '$($Releases.PSBase.Count)' releases with commits";

        $Releases.PSBase.Keys | Sort-Object -Descending | ForEach-Object {

          Write-host "    ~~~ RELEASE: '$_' ~~~";
          Write-Host "";
          [string]$tag = $_.ToString();
          [PSCustomObject]$releaseObj = $Releases[$tag];

          if ($releaseObj) {
            if (${releaseObj}?.Squashed) {
              $squashedCount = $releaseObj.Squashed.PSBase.Count;

              [string[]]$keys = $releaseObj.Squashed.PSBase.Keys
              foreach ($issue in $keys) {
                $squashedItem = $releaseObj.Squashed[$issue];

                if ($squashedItem -is [System.Collections.Generic.List[PSCustomObject]]) {
                  foreach ($squashed in $squashedItem) {
                    Write-Host "      --- SQUASHED COMMIT ($issue): '$($squashed.Subject)'";
                  }
                }
                else {
                  Write-Host "      +++ UN-SQUASHED COMMIT ($issue): '$($squashedItem.Subject)'";
                }
              }
            }

            if (${releaseObj}?.Commits) {
              $commitsCount = $releaseObj.Commits.Count;

              foreach ($comm in $releaseObj.Commits) {
                Write-Host "      /// OTHER COMMIT: '$($comm.Subject)'";
              }
            }

            Write-Host "    >>> Tag (until): '$_', Squashed: '$squashedCount', commitsCount: '$commitsCount'"

            if ($changer) {
              $changer.CountCommits
            }
          }
          Write-Host "";
        }
      }
    }
  }

  Context 'GetTagsInRange' {
    Context 'given: OrderBy descending' {
      Context 'and: full history (no tags defined)' {
        It 'should: return all tags' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 10;
            $result[1].Version.CompareTo([system.version]::new(3, 0, 2).ToString()) | Should -Be 0;
            $result[9].Version.CompareTo([system.version]::new(1, 0, 0).ToString()) | Should -Be 0;
          }
        }
      } # and: full history

      Context 'and: full history (until = HEAD)' {
        It 'should: return all tags' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = 'HEAD';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 10;

            $result[1].Version.CompareTo([system.version]::new(3, 0, 2).ToString()) | Should -Be 0;
            $result[9].Version.CompareTo([system.version]::new(1, 0, 0).ToString()) | Should -Be 0;
          }
        }
      } # and: full history (until = HEAD)

      Context 'and: un-released' {
        It 'should: return last release' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Unreleased = $true;
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 1;
            $result[0].Label | Should -BeExactly 'HEAD';
          }
        }
      } # and: un-released

      Context 'and: since specified tag' {
        It 'should: return tags since' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From = '3.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 4;
            $result[1].Version.CompareTo([system.version]::new(3, 0, 2).ToString()) | Should -Be 0;
            $result[3].Version.CompareTo([system.version]::new(3, 0, 0).ToString()) | Should -Be 0;
          }
        }
      } # and: since specified tag

      Context 'and: until specified tag' {
        It 'should: return tags until' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = '3.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 7;
            $result[0].Version.CompareTo([system.version]::new(3, 0, 0).ToString()) | Should -Be 0;
            $result[6].Version.CompareTo([system.version]::new(1, 0, 0).ToString()) | Should -Be 0;
          }
        }
      } # and: until specified tag

      Context 'and: between 2 specified tags' {
        It 'should: return tags in range' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '3.0.0';
              Until = '3.0.2';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 3;
            $result[0].Version.CompareTo([system.version]::new(3, 0, 2).ToString()) | Should -Be 0;
            $result[2].Version.CompareTo([system.version]::new(3, 0, 0).ToString()) | Should -Be 0;
          }
        }

        It 'should: return tags in range' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '1.1.1';
              Until = '1.2.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 2;
            $result[0].Version.CompareTo([system.version]::new(1, 2, 0).ToString()) | Should -Be 0;
            $result[1].Version.CompareTo([system.version]::new(1, 1, 1).ToString()) | Should -Be 0;
          }
        }

        It 'should: return tags in range' {
          InModuleScope Elizium.PoShLog {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = '1.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 1;
            $result[0].Version.CompareTo([system.version]::new(1, 0, 0).ToString()) | Should -Be 0;
          }
        }
      } # and: between 2 specified tags
    } # given: OrderBy descending
  } # GetTagsInRange

  Context 'getRange' {
    BeforeEach {
      InModuleScope Elizium.PoShLog {
        function initialize-WithTagIndices {
          #     0,     1,     2,     3,     4,     5,     6,     7,     8
          # 3.0.2, 3.0.1, 3.0.0, 2.0.0, 1.2.0, 1.1.1, 1.1.0, 1.0.1, 1.0.0
          #
          [OutputType([hashtable])]
          param(
            [object]$changeLog
          )
          $changeLog.Init();

          [array]$tagsInRange = $changeLog.TagsInRangeWithHead;
          [hashtable]$indexOfTag = @{};

          [string[]]$labelSequence = $tagsInRange.Label;
          [int]$counter = 0;

          $labelSequence | ForEach-Object {
            $indexOfTag[$_] = $counter++; 
          }

          return [PSCustomObject]@{
            IndexOfTag  = $indexOfTag;
            TagsInRange = $tagsInRange;
          }
        }

        [PSCustomObject]$result = initialize-WithTagIndices -changeLog $_changeLog;
        [hashtable]$script:_indexOfTag = $result.IndexOfTag;
        [array]$script:_tagsInRange = $result.TagsInRange;
      }
    }

    Context 'given: OrderBy descending' {
      Context 'and: current is HEAD' {
        It 'should: return correct range latest to HEAD' {
          InModuleScope Elizium.PoShLog {
            [PSCustomObject]$current = $_head;

            $_changeLog.getRange($current, $_tagsInRange).Range | Should -BeExactly '3.0.2..HEAD';
          }
        }
      } # and: full history

      Context 'and: current is earliest tag' {
        It 'should: return current by itself' {
          InModuleScope Elizium.PoShLog {
            [PSCustomObject]$current = $_tagsInRange[$_indexOfTag['1.0.0']];

            $_changeLog.getRange($current, $_tagsInRange).Range | Should -BeExactly '1.0.0';
          }
        }
      }

      Context 'and: current is midway through tag sequence' {
        It 'should: return current as until, and the previous (earlier) as from' {
          InModuleScope Elizium.PoShLog {
            [PSCustomObject]$current = $_tagsInRange[$_indexOfTag['1.2.0']];

            $_changeLog.getRange($current, $_tagsInRange).range | Should -BeExactly '1.1.1..1.2.0';
          }
        }
      }
    } # given: OrderBy descending
  } #getRange

  Describe 'Tag Validation' {
    Context 'given: Unreleased specified' {
      Context 'and: From is present' {
        It 'should: throw' {
          InModuleScope Elizium.PoShLog {
            {
              $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                Until      = '1.0.0';
                Unreleased = $true;
              }
              $_changeLog.Init();
            } | Should -Throw;
          }
        }
      }

      Context 'and: Until is present' {
        It 'should: throw' {
          InModuleScope Elizium.PoShLog {
            {
              $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                From       = '1.0.0';
                Unreleased = $true;
              }
              $_changeLog.Init();
            } | Should -Throw;
          }
        }
      }
    }

    Context 'given: unknown tag is specified' {
      It 'should: throw' {
        InModuleScope Elizium.PoShLog {
          {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From = '1.0.0-blooper';
            }
            $_changeLog.Init();
          } | Should -Throw;
        }
      }
    }

    Context 'given: From and Until specified in wrong order' {
      It 'should: throw' {
        InModuleScope Elizium.PoShLog {
          {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '3.0.0';
              Until = '1.0.0';
            }
            $_changeLog.Init();
          } | Should -Throw;          
        }
      }
    }
  }

  Context 'processCommits' {
    Context 'given: SquashBy enabled' {
      Context 'given: OrderBy descending' {
        Context 'and: IncludeMissingIssue enabled' {
          Context 'given: full history (no tags defined)' {
            It 'should: return commits for all tags' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                # Show-Releases -Releases $releases;

                $releases.PSBase.Count | Should -Be 10;
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # given: full history (no tags defined)

          Context 'given: full history (until = HEAD)' {
            It 'should: return commits for all tags' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Until = 'HEAD';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();

                $releases.PSBase.Count | Should -Be 10;
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # given: full history (until = HEAD)

          Context 'and: un-released' {
            It 'should: return commits since last release' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Unreleased = $true;
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 1;
                # Un-squashed
                #
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # and: un-released

          Context 'and: since specified tag' {
            It 'should: return commits since' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 4;
                # Un-Squashed
                #
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
                $releases['3.0.2'].Squashed['151'].Subject | `
                  Should -BeExactly "fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux";
                $releases['3.0.1'].Squashed['145'].Subject | `
                  Should -BeExactly "feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline";
                $releases['3.0.1'].Squashed['147'].Subject | `
                  Should -BeExactly "chore(pstools): #147 get-CommandDetail is now an internal function";
              }
            }
          } # and: since specified tag

          Context 'and: until specified tag' {
            It 'should: return commits until' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Until = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 7;
                # Releases that are verified in other tests are omitted for brevity
                # (3.0.0 and 1.2.0)

                # Un-Squashed
                #
                $releases['1.1.1'].Squashed['35'].Subject | `
                  Should -BeExactly "(fix #35): Catch the MethodInvocationException";

                $releases['2.0.0'].Squashed['98'].Subject | `
                  Should -BeExactly "(fix #98): Rename Select-Text to Select-Patterns";

                $releases['2.0.0'].Squashed['89'].Subject | `
                  Should -BeExactly "(doc #89): fix typos in README";

                # Squashed
                #
                [array]$squashed24 = $releases['1.1.0'].Squashed['24'];
                $squashed24.Count | Should -Be 2;

                [string[]]$subjects24 = $squashed24.Subject;
                $subjects24 | `
                  Should -Contain '(feat #24): Export functions and variables properly via psm';
                $subjects24 | `
                  Should -Contain '(feat #24): dont add files to FunctionsToExport if they are not of the form verb-noun';
              }
            }
          } # and: until specified tag

          Context 'and: between 2 specified tags' {
            It 'should: return commits in range' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '3.0.0';
                  Until = '3.0.2';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 3;
                # Un-squashed
                #
                $releases['3.0.2'].Squashed['151'].Subject | `
                  Should -BeExactly "fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux";

                $releases['3.0.1'].Squashed['145'].Subject | `
                  Should -BeExactly "feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline";

                $releases['3.0.1'].Squashed['147'].Subject | `
                  Should -BeExactly "chore(pstools): #147 get-CommandDetail is now an internal function";
              }
            }

            It 'should: return commits in range' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '1.1.1';
                  Until = '1.2.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 2;
                # Squashed
                #
                [array]$squashed34 = $releases['1.2.0'].Squashed['34'];
                [array]$squashed36 = $releases['1.2.0'].Squashed['36'];
                $squashed34.Count | Should -Be 2;
                $squashed36.Count | Should -Be 3;

                [string[]]$subjects34 = $squashed34.Subject;
                $subjects34 | Should -Contain '(fix #34): Make tests platform friendly (break on first item)';
                $subjects34 | Should -Contain '(fix #34)!: Fix Tests broken on mac';

                [string[]]$subjects36 = $squashed36.Subject;
                $subjects36 | Should -Contain '(fix #36): Minor controller/test improvements';
                $subjects36 | Should -Contain '(fix #36): Add controller tests';
                $subjects36 | Should -Contain '(fix #36): Fix New-Controller parameter sets';
              }
            }

            It 'should: return commits in range' {
              InModuleScope Elizium.PoShLog {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '2.0.0';
                  Until = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 2;
                # Squashed
                #
                [array]$squashed127 = $releases['3.0.0'].Squashed['127'];
                $squashed127.Count | Should -Be 4;

                [string[]]$subjects127 = $squashed127.Subject;
                $subjects127 | Should -Contain '(doc #127): Minor docn tweaks';
                $subjects127 | Should -Contain '(doc #127): Add boostrap docn';
                $subjects127 | Should -Contain '(doc #127): Fix links in markdown';
                $subjects127 | Should -Contain '(doc #127): Add docn for Test-IsAlreadyAnchoredAt';

                # Un-Squashed
                #
                $releases['3.0.0'].Squashed['64'].Subject | `
                  Should -BeExactly "(fix #64)!: Add Trigger count to Summary";
              }
            }
          } # and: between 2 specified tags
        } # and: IncludeMissingIssue enabled
      } # given: OrderBy descending
    } # given: SquashBy enabled

    Context 'given: SquashBy NOT enabled' {
      Context 'given: OrderBy descending' {
        Context 'given: full history (no tags defined)' {
          It 'should: return commits for all tags' {
            InModuleScope Elizium.PoShLog {
              $_options.Selection.SquashBy = [string]::Empty;
              [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
              $changeLog.Init();

              [hashtable]$releases = $changeLog.processCommits();
              $releases.PSBase.Count | Should -Be 10;

              $releases['HEAD'].Commits.Count | Should -Be 1;
              $releases['3.0.2'].Commits.Count | Should -Be 1;
              $releases['3.0.1'].Commits.Count | Should -Be 2;
              $releases['3.0.0'].Commits.Count | Should -Be 5;
              $releases['2.0.0'].Commits.Count | Should -Be 2;
              $releases['1.2.0'].Commits.Count | Should -Be 5;
              $releases['1.1.1'].Commits.Count | Should -Be 1;
              $releases['1.1.0'].Commits.Count | Should -Be 2;
              $releases['1.0.1'].Commits.Count | Should -Be 0; # (subject: "Bump version to 1.0.1")
            }
          } # should: return commits for all tags
        } # given: full history (no tags defined)
      } # given: OrderBy descending
    } # given: SquashBy NOT enabled

    Context 'given: repo contains no Tags' {
      It 'should: handle gracefully' {
        InModuleScope Elizium.PoShLog {
          [hashtable]$overrides = [hashtable]::new($_overrides);
          $overrides['ReadLogTags'] = $_noTagsInRepo;

          [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $overrides;
          $changeLog.Init();
          [hashtable]$releases = $changeLog.processCommits();
          $releases | Should -Not -BeNullOrEmpty;
        }
      }
    }
  } # processCommits

  Context 'composePartitions' {
    Context 'and: full history (no tags defined)' {
      Context 'given: GroupBy path: scope/type' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.PoShLog {
            $_options.Output.GroupBy = 'scope/type';
            [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['foo']['fix'].Count | Should -Be 1;
            $releases[0].Partitions['foo']['fix'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['signals']['fix'].Count | Should -Be 1;
            $releases[1].Partitions['signals']['fix'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['pstools']['feat'].Count | Should -Be 1;
            $releases[2].Partitions['pstools']['feat'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['pstools']['chore'].Count | Should -Be 1;
            $releases[2].Partitions['pstools']['chore'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            $releases[3].Tag.Label | Should -Be '3.0.0';
            $releases[3].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[3].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #64)!:') | Should -BeTrue;
            $releases[3].Partitions['uncategorised']['doc'].Count | Should -Be 1;
            $releases[3].Partitions['uncategorised']['doc'][0].Subject.StartsWith('(doc #127):') | Should -BeTrue;

            $releases[4].Tag.Label | Should -Be '2.0.0';
            $releases[4].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[4].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #98):') | Should -BeTrue;
            $releases[4].Partitions['uncategorised']['doc'].Count | Should -Be 1;
            $releases[4].Partitions['uncategorised']['doc'][0].Subject.StartsWith('(doc #89):') | Should -BeTrue;

            $releases[5].Tag.Label | Should -Be '1.2.0';
            $releases[5].Partitions['uncategorised']['fix'].Count | Should -Be 2;
            $releases[5].Partitions['uncategorised']['fix'] | Where-Object { # Can't rely on order, so search!
              $_.Subject.StartsWith('(fix #36):')
            } | Should -Not -BeNullOrEmpty;
            $releases[5].Partitions['uncategorised']['fix'] | Where-Object {
              $_.Subject.StartsWith('(fix #34)!:')
            } | Should -Not -BeNullOrEmpty;

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[6].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['uncategorised']['feat'].Count | Should -Be 1;
            $releases[7].Partitions['uncategorised']['feat'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        } # should: compose change log partitions
      } # given: GroupBy path: scope/type

      Context 'given: GroupBy path: type/scope' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.PoShLog {
            $_options.Output.GroupBy = 'type/scope';
            [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['fix']['foo'].Count | Should -Be 1;
            $releases[0].Partitions['fix']['foo'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['fix']['signals'].Count | Should -Be 1;
            $releases[1].Partitions['fix']['signals'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['feat']['pstools'].Count | Should -Be 1;
            $releases[2].Partitions['feat']['pstools'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['chore']['pstools'].Count | Should -Be 1;
            $releases[2].Partitions['chore']['pstools'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            $releases[3].Tag.Label | Should -Be '3.0.0';
            $releases[3].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[3].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #64)!:') | Should -BeTrue;
            $releases[3].Partitions['doc']['uncategorised'].Count | Should -Be 1;
            $releases[3].Partitions['doc']['uncategorised'][0].Subject.StartsWith('(doc #127):') | Should -BeTrue;

            $releases[4].Tag.Label | Should -Be '2.0.0';
            $releases[4].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[4].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #98):') | Should -BeTrue;
            $releases[4].Partitions['doc']['uncategorised'].Count | Should -Be 1;
            $releases[4].Partitions['doc']['uncategorised'][0].Subject.StartsWith('(doc #89):') | Should -BeTrue;

            $releases[5].Tag.Label | Should -Be '1.2.0';
            $releases[5].Partitions['fix']['uncategorised'].Count | Should -Be 2;
            $releases[5].Partitions['fix']['uncategorised'] | Where-Object { # Can't rely on order, so search!
              $_.Subject.StartsWith('(fix #36):')
            } | Should -Not -BeNullOrEmpty;
            $releases[5].Partitions['fix']['uncategorised'] | Where-Object {
              $_.Subject.StartsWith('(fix #34)!:')
            } | Should -Not -BeNullOrEmpty;

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[6].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['feat']['uncategorised'].Count | Should -Be 1;
            $releases[7].Partitions['feat']['uncategorised'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        }
      } # given: GroupBy path: type/scope

      Context 'given: GroupBy path: type' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.PoShLog {
            $_options.Output.GroupBy = 'type';
            [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['fix'].Count | Should -Be 1;
            $releases[0].Partitions['fix'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['fix'].Count | Should -Be 1;
            $releases[1].Partitions['fix'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['feat'].Count | Should -Be 1;
            $releases[2].Partitions['feat'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['chore'].Count | Should -Be 1;
            $releases[2].Partitions['chore'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            # ...
            #
          }
        }
      } # given: GroupBy path: type

      Context 'given: GroupBy path: scope' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.PoShLog {
            $_options.Output.GroupBy = 'scope';
            [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            #
            # ...

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[6].Partitions['uncategorised'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[7].Partitions['uncategorised'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        } # should: compose change log partitions
      } # given: GroupBy path: scope

      Context 'given: GroupBy path: nothing' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.PoShLog {
            $_options.Output.GroupBy = [string]::Empty;
            [object]$changeLog, $null = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[0].Partitions['uncategorised'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            # ...
            #
          }
        }
      } # given: GroupBy path: nothing
    } # and: full history (no tags defined)

    Context 'Output' {
      BeforeEach {
        InModuleScope Elizium.PoShLog {
          [scriptblock]$script:_OnCommit = {
            [OutputType([string])]
            param(
              [PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('PoShLog.CommitInfo')]$commit,
              [PSTypeName('PoShLog.TagInfo')]$tagInfo,
              [PSCustomObject]$custom
            )

            Write-Debug $(
              "OnCommit: path: '$($segmentInfo.Path)', subject: '$($commit.Subject)'" +
              ", Tag: '$($tagInfo.Label)', Dirty: '$($segmentInfo.IsDirty)'"
            );
          }

          [scriptblock]$script:_OnEndBucket = {
            [OutputType([string])]
            param(
              [PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('PoShLog.TagInfo')]$tagInfo,
              [GeneratorUtils]$utils,
              [PSTypeName('PoShLog.WalkInfo')]$custom
            )
            Write-Debug $("OnEndBucket: decorated path: '$($segmentInfo.DecoratedPath)'");
          }

          [scriptblock]$script:_OnHeading = {
            [OutputType([string])]
            param(
              [string]$headingType,
              [string]$headingFormat,
              [PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('PoShLog.TagInfo')]$tagInfo,
              [GeneratorUtils]$utils,
              [PSTypeName('PoShLog.WalkInfo')]$custom
            )
            Write-Debug $("OnHeading('$($headingType)'): decorated path: '$($segmentInfo.DecoratedPath)'");
          }

          [scriptblock]$script:_OnSection = {
            [OutputType([string])]
            param(
              [string]$sectionName,
              [string]$titleStmt,
              [string[]]$content,
              [System.Management.Automation.PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
              [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$tagInfo,
              [GeneratorUtils]$utils,
              [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$custom
            )
            Write-Debug $("OnSection('$($sectionName)'): statement: '$($titleStmt)'");
          }

          [PSCustomObject]$script:_handlers = [PSCustomObject]@{
            PSTypeName = 'PoShLog.Handlers';
          }

          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnHeading' -Value $($_OnHeading);
          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnSection' -Value $($_OnSection);
          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnCommit' -Value $($_OnCommit);
          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnEndBucket' -Value $($_OnEndBucket);
        }
      } # BeforeEach

      Context 'GroupBy.Walk' {
        Context 'given: full history (no tags defined)' {
          Context 'and: GroupBy path: scope/type' {
            It 'should: compose change log partitions' {
              InModuleScope Elizium.PoShLog {
                $_options.Output.GroupBy = 'scope/type';

                [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
                $changeLog.Init();

                [array]$releases = $changeLog.composePartitions();
                [PSCustomObject]$customWalkInfo = [PSCustomObject]@{
                  PSTypeName = 'PoShLog.WalkInfo';
                  #
                  Appender   = [LineAppender]::new()
                  Options    = $_options;
                }

                foreach ($release in $releases) {
                  $dependencies.Grouper.Walk($release, $_handlers, $customWalkInfo);
                }
              }
            }
          }
        }
      } # GroupBy.Walk

      Context 'MarkdownPoShLogGenerator.Generate' {
        Context 'given: full history (no tags defined)' {
          It 'should: generate content' {
            InModuleScope Elizium.PoShLog {
              [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
              $changeLog.Init();

              [array]$releases = $changeLog.composePartitions();
              [object]$template = $_options.Output.Template;
              [string]$content = $dependencies.Generator.Generate(
                $releases, $template, $changeLog.TagsInRangeWithHead
              );
              $content | Should -Not -BeNullOrEmpty;
            }
            # rel, template
          }

          Context 'and: no GroupBy' {
            It 'should: generate content' {
              InModuleScope Elizium.PoShLog {
                $_options.Selection.Tags = @{
                  PSTypeName = 'PoShLog.Options.Selection.Tags';
                  Until      = '1.0.1';
                }
                $_options.Output.GroupBy = [string]::Empty;
                $_options.Output.Headings.H3 = '*{ungroupedStmt}';

                [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
                $changeLog.Init();

                [array]$releases = $changeLog.composePartitions();
                [object]$template = $_options.Output.Template;
                [string]$content = $dependencies.Generator.Generate(
                  $releases, $template, $changeLog.TagsInRangeWithHead
                );
                $content | Should -Not -BeNullOrEmpty;
              }
            }
          } # and: no GroupBy
        } # given: full history (no tags defined)

        Context 'given: repo contains no Tags' {
          It 'should: handle gracefully' {
            InModuleScope Elizium.PoShLog {
              [hashtable]$overrides = [hashtable]::new($_overrides);
              $overrides['ReadLogTags'] = $_noTagsInRepo;

              [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $overrides;
              $changeLog.Init();

              [array]$releases = $changeLog.composePartitions();
              [object]$template = $_options.Output.Template;
              [string]$content = $dependencies.Generator.Generate(
                $releases, $template, $changeLog.TagsInRangeWithHead
              );
              $content | Should -Not -BeNullOrEmpty;
            }
          }
        }        
      } # MarkdownPoShLogGenerator.Generate

      Context 'given: MarkdownPoShLogGenerator.CreateComparisonLinks' {
        It 'should: generate content' {
          InModuleScope Elizium.PoShLog {
            [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [string]$content = $dependencies.Generator.CreateComparisonLinks(
              $changeLog.TagsInRangeWithHead
            );
            $content | Should -Not -BeNullOrEmpty;
          }
        }
      }

      Context 'given: MarkdownPoShLogGenerator.CreateDisabledWarnings' {
        It 'should: generate content' {
          InModuleScope Elizium.PoShLog {
            [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
            $changeLog.Init();

            [string]$content = $dependencies.Generator.CreateDisabledWarnings();
            $content | Should -Not -BeNullOrEmpty;
          }
        }
      }
    }

    Context 'given: repo contains no Tags' {
      It 'should: handle gracefully' {
        InModuleScope Elizium.PoShLog {
          [hashtable]$overrides = [hashtable]::new($_overrides);
          $overrides['ReadLogTags'] = $_noTagsInRepo;

          [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $overrides;
          $changeLog.Init();

          [array]$releases = $changeLog.composePartitions();
          $releases.Count -eq 0;
        }
      }
    }
  } # composePartitions

  Describe 'given: PoShLog with Git' {
    Context 'and: klassy' {
      It 'should: Build real change log' {
        InModuleScope Elizium.PoShLog {
          [object]$changeLog = New-PoShLog -Options $_options;
          $changeLog.Init();

          [string]$content = $changeLog.Build();
          $content | Should -Not -BeNullOrEmpty;

          [string]$outputFile = 'ChangeLog-test.md';
          [string]$outputPath = Join-Path -Path $TestDrive -ChildPath $outputFile;
          $changeLog.Save($content, $outputPath);

          Test-Path -LiteralPath $outputPath | Should -BeTrue;
        }
      }
    }
  } # given: PoShLog with Git

  Describe 'GeneratorUtils' {
    Context 'Evaluate' {
      BeforeEach {
        InModuleScope Elizium.PoShLog {
          [string]$script:_subject = 'feat(pstools)!: #145 Allow command to be invoked ...';
          [hashtable]$selectors = @{
            'scope'  = 'pstools';
            'type'   = 'feat';
            'change' = 'add';
          }
          [regex]$includeRegex = [regex]::new($_includes[1]);
          [System.Text.RegularExpressions.GroupCollection]$groups = `
            $includeRegex.Matches($_subject)[0].Groups;

          [PSCustomObject]$script:_commit = [PSCustomObject]@{
            PSTypeName = 'PoShLog.CommitInfo';
            #
            Date       = [DateTime]::Parse('2021-04-19 16:17:04 +0100');
            CommitId   = 'dc800c6';
            FullHash   = 'dc800c68e4aaa6be692c8254490945ad73f69e6d';
            Author     = 'plastikfan';
            Subject    = $_subject;
            Info       = [PSCustomObject]@{ # => this replicates 'GroupByImpl.Partition'
              PSTypeName = 'PoShLog.CommitInfo';
              Selectors  = $selectors;
              IsBreaking = $groups.ContainsKey('break') -and $groups['break'].Success;
              Groups     = $groups;
            }
            IsSquashed = $true;
          }

          [hashtable]$script:_variables = @{
            'author'        = $_commit.Author;
            'avatar-img'    = "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>";
            'commitid'      = 'dc800c6';
            'commitid-link' = $("[dc800c6](https://github.com/EliziumNet/Loopz/" +
              "commit/dc800c68e4aaa6be692c8254490945ad73f69e6d)");
            'is-breaking'   = $_commit.Info.IsBreaking;
            'is-squashed'   = $true;
            'issue-link'    = "[#145](https://github.com/EliziumNet/Loopz/issues/145)";
            'subject'       = $_subject;
            'scope'         = 'pstools';
            'type'          = 'feat';
          }
        }
      }

      Context 'given: commit' {
        Context 'and: Statement <statement>' {
          It 'should: fully resolve to be "<expected>"' -TestCases @(
            @{
              Statement = 'AUTHOR:*{authorStmt}';
              Expected  = $(
                "AUTHOR: by ``@plastikfan`` :bird:"
              )
            },

            @{
              Statement = 'AVATAR:*{avatarStmt}';
              Expected  = $(
                "AVATAR: by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              )
            },

            @{
              Statement = '?{is-breaking;breakStmt}';
              Expected  = ':warning: *BREAKING CHANGE* ';
            }

            @{
              Statement = '[Change Type: &{_C}+{change}] => ';
              Expected  = '[Change Type: :lock:] => ';
            },

            @{
              Statement = '?{change;changeStmt}';
              Expected  = [string]::Empty
            },

            @{
              Statement = '+ ?{break;breakStmt}*{changeStmt}*{subjectStmt}*{avatarStmt}';
              Expected  = $(
                "+ " +
                ":warning: *BREAKING CHANGE* " +
                "[Change Type: :lock:] => " +
                "Subject: **feat(pstools)!: #145 Allow command to be invoked ...**" +
                " by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              );
            },

            @{
              Statement = '+ ?{break;breakStmt}?{change;changeStmt}*{subjectStmt}*{avatarStmt}';
              Expected  = $(
                "+ " +
                ":warning: *BREAKING CHANGE* " +
                "Subject: **feat(pstools)!: #145 Allow command to be invoked ...**" +
                " by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              );
            },

            @{
              Statement = '!{dirty}';
              Expected  = ':poop:';
            },

            @{
              Statement = 'Scope(&{_S} +{scope})';
              Expected  = 'Scope(:parking: pstools)';
            },

            @{
              Statement = 'SQUASHED: *{subjectStmt}';
              Expected  = $(
                'SQUASHED: Subject: **feat(pstools)!: #145 Allow command to be invoked ...**'
              )
            },

            @{
              Statement = '?{is-squashed;squashedStmt}';
              Expected  = 'SQUASHED: ';
            },

            @{
              Statement = 'Subject: **+{subject}**';
              Expected  = 'Subject: **feat(pstools)!: #145 Allow command to be invoked ...**';
            },

            @{
              Statement = 'Commit-Type(&{_T} +{type})';
              Expected  = 'Commit-Type(:gift: feat)';
            },

            @{
              Statement = 'BODY: ^{body}';
              Expected  = 'BODY: Allow command to be invoked ...';
            },

            @{
              Statement = 'META INFO:*{metaStmt}';
              Expected  = $(
                'META INFO: (Id: [dc800c6](https://github.com/EliziumNet/Loopz/commit/dc800c68e4aaa6be692c8254490945ad73f69e6d))' +
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '*{metaStmt}';
              Expected  = $(
                ' (Id: [dc800c6](https://github.com/EliziumNet/Loopz/commit/dc800c68e4aaa6be692c8254490945ad73f69e6d))' +
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '?{issue-link;issueLinkStmt}';
              Expected  = $(
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '?{no-such-variable;issueLinkStmt}';
              Expected  = [string]::Empty;
            }
          ) {
            InModuleScope Elizium.PoShLog -Parameters @{ Statement = $statement; Expected = $expected } {
              [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
              Param(
                [string]$statement,
                [string]$expected
              )
              [object]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
              $changeLog.Init();

              $_variables['avatar-img'] = $dependencies.Generator._utils.AvatarImg($_commit.Author);

              [string]$result = $dependencies.Generator._utils.Evaluate(
                $Statement, $_commit, $_variables
              );
              [boolean]$assertion = $result.StartsWith($expected);
              if (-not($assertion)) {
                Write-Host $("FAILED: Statement: '$($Statement)'");
                Write-Host $("+ EXPECT: '$($expected)'");
                Write-Host $("+ ACTUAL: '$($result)'");
              }
              $assertion | Should -BeTrue;

              # Make sure every statement evaluated can run ok without a commit object
              # as is the case when a heading invokes Evaluate.
              #
              [void]$dependencies.Generator._utils.Evaluate(
                $Statement, $null, $_variables
              );
            }
          }
        }
      } # given: commit

      Context 'given: config error' {
        Context 'and: Statement <statement>' {
          It 'should: should throw "<because>"' -TestCases @(
            @{
              Statement = '*{blooperStmt}';
              Because   = "'blooperStmt' is not a defined statement";
            },

            @{
              Statement = '?{is-breaking;blooperStmt}';
              Because   = "'blooperStmt' is not a defined conditional statement";
            },

            @{
              Statement = '!{blooper}';
              Because   = "'blooper' is not a defined literal";
            },

            @{
              Statement = '[Change Type: &{_X}+{change}] => ';
              Because   = "'_X' is not a defined lookup";
            }
          ) {
            InModuleScope Elizium.PoShLog -Parameters @{ Statement = $statement; Because = $because } {
              Param(
                [string]$statement,
                [string]$because
              )
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
              $changeLog.Init();

              $_variables['avatar-img'] = $dependencies.Generator._utils.AvatarImg($_commit.Author);

              {
                $dependencies.Generator._utils.Evaluate(
                  $Statement, $_commit, $_variables
                );
              } | Should -Throw -Because $because;
            }
          }
        }

        Context 'and: recursive Statement' {
          It 'should: throw' {
            InModuleScope Elizium.PoShLog {
              $_options.Output.Statements = [PSCustomObject]@{
                PSTypeName = 'PoShLog.Options.Output.Statements';
                #
                Break      = '*{breakStmt} *BREAKING CHANGE* ';
              }
              [string]$statement = $_options.Output.Statements.Break;
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Overrides $_overrides;
              $changeLog.Init();

              {
                $dependencies.Generator._utils.Evaluate(
                  $statement, $_commit, $_variables
                );
              } | Should -Throw;
            }
          }
        }

        Context 'and: recursive Conditional Statement' {
          It 'should: throw' {
            InModuleScope Elizium.PoShLog {
              $_options.Output.Statements = [PSCustomObject]@{
                PSTypeName = 'PoShLog.Options.Output.Statements';
                #
                Break      = '?{is-breaking;breakStmt} *BREAKING CHANGE* ';
              }
              [string]$statement = $_options.Output.Statements.Break;
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = New-TestChangeLog -Options $_options -Override $_overrides;
              $changeLog.Init();

              {
                $dependencies.Generator._utils.Evaluate(
                  $statement, $_commit, $_variables
                );
              } | Should -Throw;
            }
          }
        }
      } # given: config error
    } # Evaluate

    Context 'CreateIsaLookup' {
      Context 'given: simple parent' {
        It 'should: return remapped value' {
          [hashtable]$optionTypes = @{
            "Performance" = ":hammer:";
            "perf"        = "isa:Performance";
          }
          [PSCustomObject]$types = [GeneratorUtils]::CreateIsaLookup(
            'Types', $optionTypes
          );
          [string]$type = 'perf';

          $types.Isa[$type] | Should -BeExactly 'Performance';
          $types.Value[$type] | Should -BeExactly ':hammer:'; 
        }
      }

      Context 'given: parent with spaces' {
        It 'should: return remapped value' {
          [hashtable]$optionScopes = @{
            "Parameter Set Tools" = ":postbox:";
            "pstools"             = "isa:Parameter Set Tools";
          }
          [PSCustomObject]$scopes = [GeneratorUtils]::CreateIsaLookup(
            'Scopes', $optionScopes
          );
          [string]$scope = 'pstools';

          $scopes.Isa[$scope] | Should -BeExactly 'Parameter Set Tools';
          $scopes.Value[$scope] | Should -BeExactly ':postbox:';
        }
      }

      Context 'given: entry refers to itself' {
        It 'should: throw' {
          {
            [GeneratorUtils]::CreateIsaLookup('Scopes', @{
                "Parameter Set Tools" = ":postbox:";
                "pstools"             = "isa:pstools";
              });
          } | Should -Throw;
        }
      }

      Context 'given: entry refers to non existent parent' {
        It 'should: throw' {
          {
            [GeneratorUtils]::CreateIsaLookup('Scopes', @{
                "Parameter Set Tools" = ":postbox:";
                "pstools"             = "isa:blooper";
              });
          } | Should -Throw;
        }
      }
    }
  } # GeneratorUtils

  Describe 'ProxyGit' {
    BeforeEach {
      [object]$script:_realGitProxy = [ProxyGit]::new();
    }

    Context 'given: HeadDate' {
      It 'should: invoke ok' {
        [string]$result = $_realGitProxy.HeadDate();
        $result | Should -Not -BeNullOrEmpty $result;
      }
    }

    Context 'given: LogTags' {
      It 'should: invoke ok' -Tag 'Current' {
        $_realGitProxy.LogTags();
        # $result | Should -Not -BeNullOrEmpty $result;
      }
    }

    Context 'given: LogRange' {
      It 'should: invoke ok' {
        [array]$result = $_realGitProxy.LogRange('HEAD', "%ai$($delim)%H$($delim)%an$($delim)%s");
        $result | Should -Not -BeNullOrEmpty $result;
      }
    }

    Context 'given: Remote' {
      It 'should: invoke ok' {
        [string]$result = $_realGitProxy.Remote();
        $result | Should -Not -BeNullOrEmpty $result;
      }
    }

    Context 'given: Root' {
      It 'should: invoke ok' {
        [string]$result = $_realGitProxy.Root();
        $result | Should -Not -BeNullOrEmpty $result;
      }
    }
  }

  Describe 'PoShLogOptionsManager' {
    Context 'given: requested <name> options does exist' {
      It 'should: create new options' -TestCases @(
        @{ Name = 'Alpha' },
        @{ Name = 'Elizium' },
        @{ Name = 'Zen' },
        @{ Name = 'Unicorn' }
      ) {
        InModuleScope Elizium.PoShLog -Parameters @{ Name = $name; } {
          param(
            [string]$Name
          )
          [string]$root = 'root';
          [string]$rootPath = Join-Path -Path $TestDrive -ChildPath $root;
          [PSCustomObject]$optionsInfo = [PSCustomObject]@{
            Base          = '-changelog.options';
            DirectoryName = [PoShLogProfile]::DIRECTORY;
            GroupBy       = 'scope/type/change/break';
            Root          = $rootPath;
          }

          # [PoShLogOptionsManager]
          [object]$manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
          [boolean]$withEmoji = $true;

          [PSCustomObject]$options = $manager.FindOptions($Name, $withEmoji);
          $manager.Found | Should -BeFalse;
          $options | Should -Not -BeNullOrEmpty;

          [object]$changeLog = New-PoShLog -Options $options;
          $changeLog.Build() | Should -Not -BeNullOrEmpty;
        }
      }
    }

    Context 'given: requested options exist' {
      It 'should: load existing options and build' {
        InModuleScope Elizium.PoShLog {
          [string]$directoryName = [PoShLogProfile]::DIRECTORY;
          [string]$root = 'root';
          [string]$rootPath = Join-Path -Path $TestDrive -ChildPath $root;
          [PSCustomObject]$optionsInfo = [PSCustomObject]@{
            Base          = '-changelog.options';
            DirectoryName = $directoryName;
            GroupBy       = 'scope/type/change/break';
            Root          = $rootPath;
          }
          [string]$directoryPath = Join-Path -Path $rootPath -ChildPath $directoryName;
          [string]$optionsFileName = 'Test-emoji-changelog.options.json';
          [string]$testPath = "./Tests/Data/changelog/$optionsFileName";

          [void]$(New-Item -ItemType 'Directory' -Path $directoryPath);
          [string]$destinationPath = Join-Path -Path $directoryPath -ChildPath $optionsFileName;
          Copy-Item -LiteralPath $testPath -Destination $destinationPath;

          # [PoShLogOptionsManager]
          [object]$manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
          [boolean]$withEmoji = $true;

          [PSCustomObject]$options = $manager.FindOptions('Test', $withEmoji);
          $manager.Found | Should -BeTrue;
          $options | Should -Not -BeNullOrEmpty;

          [object]$changeLog = New-PoShLog -Options $options;
          $changeLog.Build() | Should -Not -BeNullOrEmpty; ;
        }
      }
    }

    Context 'given: json-schema' {
      It 'should: validate options ok' {
        InModuleScope Elizium.PoShLog {
          [string]$optionsFileName = 'Test-emoji-changelog.options.json';
          [string]$testPath = "./Tests/Data/changelog/$($optionsFileName)";
          [string]$schemaFileName = [PoShLogProfile]::OPTIONS_SCHEMA_FILENAME;
          [string]$schemaPath = "./FileList/$($schemaFileName)";
          [string]$json = Get-Content -LiteralPath $testPath;
          $null = Test-Json -Json $json -SchemaFile $schemaPath;
        }
      }
    }
  } # PoShLogOptionsManager
} # PoShLog
