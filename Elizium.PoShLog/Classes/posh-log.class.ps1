
# === [ SourceControl ] ========================================================
#
class SourceControl {
  [PSCustomObject]$Options;
  [PSCustomObject[]]$AllTagsWithHead;
  [PSCustomObject[]]$AllTagsWithoutHead;
  hidden [DateTime]$_headDate; # date of last commit
  hidden [DateTime]$_lastReleaseDate; # date of last release (can be null if no releases)
  static [int]$DEFAULT_COMMIT_ID_SIZE = 7;
  [int]$_commitIdSize;

  SourceControl([PSCustomObject]$options) {
    $this.Options = $options;
  }

  [void] Init([boolean]$descending) {
    [boolean]$includeHead = $true;
    $this.AllTagsWithHead = $this.ReadSortedTags($includeHead, $descending);

    $includeHead = $false;
    $this.AllTagsWithoutHead = $this.ReadSortedTags($includeHead, $descending);

    $this._commitIdSize = try {
      [int]$size = [int]::Parse($this.Options.SourceControl.CommitIdSize);
      
      $($size -in 7..40) ? $size : [SourceControl]::DEFAULT_COMMIT_ID_SIZE;
    }
    catch {
      [SourceControl]::DEFAULT_COMMIT_ID_SIZE;
    }
  }

  [PSCustomObject[]] GetSortedTags([boolean]$includeHead) {
    return $includeHead ? $this.AllTagsWithHead : $this.AllTagsWithoutHead;
  }

  [PSCustomObject[]] ReadGitTags([boolean]$includeHead) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadGitTags)');
  }

  [string] ReadRemoteUrl() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadRemoteUrl)');
  }

  [string] ReadRootPath() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadRootPath)');
  }

  [PSCustomObject[]] ReadSortedTags([boolean]$includeHead, [boolean]$descending) {

    [PSCustomObject[]]$unsorted = $this.ReadGitTags($includeHead);
    [PSCustomObject[]]$sorted = $unsorted | Sort-Object -Property 'Date' -Descending:$descending;

    return $sorted ?? @();
  }

  [PSCustomObject[]] ReadGitCommitsInRange(
    [string]$Format,
    [string]$Range,
    [string[]]$Header,
    [string]$Delim
  ) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadGitCommitsInRange)');
  }

  [DateTime] GetTagDate ([string]$Label) {
    [PSCustomObject]$foundTagInfo = $this.GetSortedTags($true) | `
      Where-Object { $_.Label -eq $Label }

    if (-not($foundTagInfo)) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        "SourceControl.GetTagDate: Tag: '$Label' not found");
    }

    return $foundTagInfo.Date;
  }

  [DateTime] GetLastReleaseDate() {
    [PSCustomObject[]]$sortedTags = $this.GetSortedTags($false);

    [DateTime]$releaseDate = if ($sortedTags.Count -gt 0) {
      $sortedTags[0].Date;
    }
    else {
      $null;
    }

    return $releaseDate;
  }

  [string[]] GetTagRange([regex]$RangeRegex, [string]$Range) {
    [System.Text.RegularExpressions.MatchCollection]$mc = $RangeRegex.Matches($Range);

    if (-not($rangeRegex.IsMatch($Range))) {
      throw "bad range: '$Range'";
    }
    [System.Text.RegularExpressions.Match]$m = $mc[0];
    [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

    [string]$from = $groups['from'];
    [string]$until = $groups['until'];

    return $from, $until;
  }

  # Returns: [PSTypeName('PoShLog.TagInfo')][array]
  #
  [PSCustomObject[]] processTags ([PSCustomObject[]]$gitTags, [boolean]$includeHead) {
    [regex]$tagRegex = "(?<dt>[^\(]+)\(tag: (?<tag>[^\)]+)\)";
    [regex]$versionRegex = [regex]::new("(?<ver>\d\.\d\.\d)");

    [array]$result = foreach ($prettyTag in $gitTags) {
      Write-Debug "SourceControl.processTags - TAG: '$prettyTag'";

      if ($tagRegex.IsMatch($prettyTag)) {
        [System.Text.RegularExpressions.MatchCollection]$mc = $tagRegex.Matches($prettyTag);
        [System.Text.RegularExpressions.Match]$m = $mc[0];
        [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

        [string]$dt = $groups['dt'].Value.Trim();
        [string]$tag = $groups['tag'].Value;
        [DateTime]$date = [DateTime]::Parse($dt)

        [PSCustomObject]$tagInfo = [PSCustomObject]@{
          PSTypeName = 'PoShLog.TagInfo';
          Label      = $tag;
          Date       = $date;
        }

        if ($versionRegex.IsMatch($tag)) {
          [System.Text.RegularExpressions.MatchCollection]$mc = $versionRegex.Matches($tag);
          [string]$version = $mc[0].Value;
          $tagInfo | Add-Member -NotePropertyName 'Version' -NotePropertyValue $version;
        }

        $tagInfo;
      }
      else {
        throw [System.Management.Automation.MethodInvocationException]::new(
          "processTags: Bad tag found: '$($prettyTag)'");
      }
    }

    if ($includeHead -and $this._headDate) {
      $result = $result += [PSCustomObject]@{
        PSTypeName = 'PoShLog.TagInfo';
        Label      = 'HEAD';
        Date       = $this._headDate;
      }
    }

    return $result;
  } # processTags
} # SourceControl

# === [ Git ] ==================================================================
#
class Git : SourceControl {
  # Ideally, _gitCi should be used to execute all git commands. However, doing so and 
  # passing in the parameters is tricky, which is the reason why git is invoked directly,
  # until the correct way to invoke with arguments has been determined.
  # The invoke options are:
  # - Call Op: & "path/blah.exe" "param1" "param2"
  # - Invoke-Command
  # - Invoke-Expression
  # - Invoke-Item
  #
  # See also:
  # https://social.technet.microsoft.com/wiki/contents/articles/7703.powershell-running-executables.aspx
  #
  hidden [System.Management.Automation.CommandInfo]$_gitCi;

  # [ProxyGit], why the hell doesn't strong typing work
  [object]$Proxy;

  # [ProxyGit]$proxy
  Git([PSCustomObject]$options, [object]$proxy): base($options) {
    $this.Proxy = $proxy;

    # Just check that git is available
    # TODO: check the digital signature
    # https://mcpmag.com/articles/2018/07/25/file-signatures-using-powershell.aspx
    #
    $this._gitCi = Get-Command 'git' -ErrorAction Stop;
    if (-not($this._gitCi -and ($this._gitCi.CommandType -eq
          [System.Management.Automation.CommandTypes]::Application))) {

      throw [System.Management.Automation.MethodInvocationException]::new(
        'git not found');
    }

    # %ai = author date, ISO 8601-like format
    # eg: '2021-04-19 18:20:49 +0100'
    #
    [string]$head = $this.Proxy.HeadDate();
    $this._headDate = [DateTime]::Parse($head);    
  } # ctor.Git

  [PSCustomObject[]] ReadGitTags([boolean]$includeHead) {
    # The 'i' in '%ci' wraps the date inside brackets and this is reflected in the regex pattern
    # %d: ref names
    # eg: '2021-04-19 18:17:15 +0100  (tag: 3.0.2)'
    #
    [array]$tags = $this.Proxy.LogTags();
    return $this.processTags($tags, $includeHead);
  } # ReadGitTags

  # Returns: [PSTypeName('PoShLog.CommitInfo')][]
  #
  [PSCustomObject[]] ReadGitCommitsInRange(
    [string]$Format,
    [string]$Range,
    [string[]]$Header,
    [string]$Delim
  ) {
    Write-Debug "ReadGitCommitsInRange: RANGE: '$($Range)', FORMAT: '$($Format)'.";

    [array]$commitContent = $this.Proxy.LogRange($Range, $Format);
    [array]$result = $commitContent | ConvertFrom-Csv -Delimiter $Delim -Header $Header;

    $result | Where-Object { $null -ne $_.CommitId } | ForEach-Object {
      Add-Member -InputObject $_ -PassThru -NotePropertyMembers @{
        PSTypeName = 'PoShLog.CommitInfo';
        FullHash   = $_.CommitId;
      }
    } | ForEach-Object {
      $_.CommitId = $_.CommitId.SubString(0, $this._commitIdSize);
      $_.Date = [DateTime]::Parse($_.Date); # convert date
    }

    return $result;
  } # ReadGitCommitsInRange

  [string] ReadRemoteUrl() {
    [string]$url = $this.Proxy.Remote();
    if ($url.EndsWith('/')) {
      $url = $url.Substring(0, $($url.Length - 1));
    }
    return $url
  }

  [string] ReadRootPath() {
    return $this.Proxy.Root();
  }
} # Git

function readHeadDate {
  [OutputType([string])]
  param()
  return $(git log -n 1 --format=%ai) ?? [string]::Empty;
}

function readLogTags {
  [OutputType([array])]
  param()
  return $((git log --tags --simplify-by-decoration --pretty="format:%ci %d") -match 'tag:') ?? @();
}

function readLogRange {
  [OutputType([array])]
  param(
    [Parameter()]
    [string]$range,

    [Parameter()]
    [string]$format
  )
  return $((git log $range --format=$format) ?? @());
}

function readRemote {
  [OutputType([string])]
  param()
  return $((git remote get-url origin) -replace '\.git$') ?? [string]::Empty;
}

function readRoot {
  [OutputType([string])]
  param()
  return $(git rev-parse --show-toplevel) ?? [string]::Empty;
}

# === [ ProxyGit ] ===========================================================
#
class ProxyGit {
  ProxyGit() {}

  # All these are designed to be overridden by tests
  #
  [scriptblock]$ReadHeadDate = $function:readHeadDate;
  [scriptblock]$ReadLogTags = $function:readLogTags;
  [scriptblock]$ReadLogRange = $function:readLogRange;
  [scriptblock]$ReadRemote = $function:readRemote;
  [scriptblock]$ReadRoot = $function:readRoot;

  [string] HeadDate() {
    return $this.ReadHeadDate.InvokeReturnAsIs();
  }

  [array] LogTags() {
    return $this.ReadLogTags.InvokeReturnAsIs();
  }

  [array] LogRange([string]$range, [string]$format) {
    return $this.ReadLogRange.InvokeReturnAsIs($range, $format);
  }

  [string] Remote() {
    return $this.ReadRemote.InvokeReturnAsIs();
  }

  [string] Root() {
    return $this.ReadRoot.InvokeReturnAsIs();
  }
}

# === [ PoShLog ] ============================================================
#
class PoShLog {
  [PSCustomObject]$Options;
  [SourceControl]$SourceControl;
  [boolean]$IsDescending;
  [PSCustomObject[]]$TagsInRangeWithHead;
  [PSCustomObject[]]$AllTagsWithHead;

  hidden [regex]$_squashRegex;
  hidden [GroupBy]$_grouper;
  hidden [PoShLogGenerator]$_generator;

  PoShLog([PSCustomObject]$options,
    [SourceControl]$sourceControl,
    [GroupBy]$grouper,
    [PoShLogGenerator]$generator) {

    $this.Options = $options;
    $this.SourceControl = $sourceControl;
    $this._grouper = $grouper;
    $this._generator = $generator;

    $this.IsDescending = $true;
    $this._grouper.SetDescending($this.IsDescending);
    $this._generator.SetDescending($this.IsDescending);

    $this._squashRegex = if (($this.Options.Selection)?.SquashBy `
        -and -not([string]::IsNullOrEmpty($this.Options.Selection?.SquashBy))) {
      [regex]::new($this.Options.Selection.SquashBy);
    }
    else {
      $null;
    }

    $sourceControl.Init($this.IsDescending);
  } # ctor.PoShLog

  [void] Init() {
    $this.AllTagsWithHead = $this.SourceControl.GetSortedTags($true);
    $this.TagsInRangeWithHead = $this.GetTagsInRange();

    if (($this.Options.Selection.Tags)?.From) {
      if (-not($this.TagIsValid($this.Options.Selection.Tags.From))) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLog.Init: From tag '$($this.Options.Selection.Tags.From)'" +
            " does not exist in this repo"
          )
        );
      }
    }

    if (($this.Options.Selection.Tags)?.Until) {
      if (-not($this.TagIsValid($this.Options.Selection.Tags.Until))) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLog.Init: Until tag '$($this.Options.Selection.Tags.Until)'" +
            " does not exist in this repo"
          )
        );
      }
    }

    if (($this.Options.Selection.Tags)?.From -and ($this.Options.Selection.Tags)?.Until) {
      if (-not($this.TagRangeIsValid(
            $this.Options.Selection.Tags.From, $this.Options.Selection.Tags.Until
          ))) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLog.Init: From tag: '$($this.Options.Selection.Tags.From)'" +
            " and Until tag: '$($this.Options.Selection.Tags.Until)'" +
            " have been specified the wrong way round. Swap the values and try again."
          )
        );
      }
    }
  }

  [boolean] TagIsValid([string]$label) {
    $found = $this.AllTagsWithHead | Where-Object {
      $_.Label -eq $label;
    }

    if (($this.Options.Selection.Tags)?.Unreleased) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $("PoShLog.Init: From tag 'Unreleased' can not be specified with '$label'")
      );
    }

    return ($null -ne $found);
  }

  [boolean] TagRangeIsValid([string]$fromLabel, [string]$untilLabel) {
    [PSCustomObject]$fromTag = $($this.AllTagsWithHead | Where-Object {
        $_.Label -eq $fromLabel;
      })?[0];

    [PSCustomObject]$untilTag = $($this.AllTagsWithHead | Where-Object {
        $_.Label -eq $untilLabel;
      })?[0];

    return [DateTime]::Compare($fromTag.Date, $untilTag.Date) -lt 0;
  }

  [string] Build() {
    [array]$releases = $this.composePartitions();
    [object]$template = $this.Options.Output.Template;
    [string]$content = $this._generator.Generate(
      $releases, $template, $this.TagsInRangeWithHead
    );

    return $content;
  }

  [void] Save([string]$content, [string]$fullPath) {
    Set-Content -LiteralPath $fullPath -Value $content;
  }

  # Return: [PSTypeName('PoShLog.PartitionedRelease')][array]
  #
  [PSCustomObject[]] composePartitions() {
    [hashtable]$releases = $this.processCommits();

    return $this._grouper.Partition($releases, $this.AllTagsWithHead);
  }

  # Returns: ('PoShLog.CommitInfo')[]
  #
  [PSCustomObject[]] GetTagsInRange() {
    [scriptblock]$whereTagsInRange = if (($this.Options.Selection.Tags)?.From -and
      ($this.Options.Selection.Tags)?.Until) {

      [scriptblock] {
        [string]$from = ($this.Options.Selection.Tags)?.From;
        [string]$until = ($this.Options.Selection.Tags)?.Until;

        [DateTime]$fromDate = $this.SourceControl.GetTagDate($from);
        [DateTime]$untilDate = $this.SourceControl.GetTagDate($until);

        $this.IsDescending ? $_.Date -ge $fromDate -and $_.Date -le $untilDate `
          : $_.Date -le $fromDate -and $_.Date -ge $untilDate;
      }
    }
    elseif (($this.Options.Selection.Tags)?.From) {
      [scriptblock] {
        [string]$from = ($this.Options.Selection.Tags)?.From;
        [DateTime]$fromDate = $this.SourceControl.GetTagDate($from);

        $this.IsDescending ? $_.Date -ge $fromDate : $_.Date -le $fromDate;
      }
    }
    elseif (($this.Options.Selection.Tags)?.Until) {
      [scriptblock] {
        [string]$until = ($this.Options.Selection.Tags)?.Until;
        [DateTime]$untilDate = $this.SourceControl.GetTagDate($until);

        $this.IsDescending ? $_.Date -le $untilDate : $_.Date -ge $untilDate;
      }
    }
    elseif (($this.Options.Selection.Tags)?.Unreleased) {
      [scriptblock] {
        [DateTime]$lastDate = $this.SourceControl.GetLastReleaseDate();

        if ($lastDate) {
          $this.IsDescending ? $_.Date -gt $lastDate : $_.Date -le $lastDate;
        }
        else {
          # There are no releases but there are commits, we should still be able
          # to build a change log
          #
          $true;
        }
      }      
    }
    else {
      [scriptblock] { $true } # => Select all tags by default
    }
    [PSCustomObject[]]$result = ($this.AllTagsWithHead | Where-Object $whereTagsInRange);

    return $result;
  } # GetTagsInRange

  # Returned releases are a hashtable keyed by tag label => [PSTypeName('PoShLog.SquashedRelease')]
  #
  [hashtable] processCommits() {

    # NB: WARNING, do not select the body; if it is multiline, then it will break
    # all of this, because the assumption is that 1 commit = 1 line of content
    #
    [string]$format = "%ai`t%H`t%an`t%s";
    [string[]]$header = @("Date", "CommitId", "Author", "Subject");
    [string]$delim = "`t";

    [hashtable]$releases = [ordered]@{}
    
    Write-Debug "=== [ processCommits: tags ($($this.TagsInRangeWithHead.Count)): '$($this.TagsInRangeWithHead.Label -join ', ')' ] ===";

    foreach ($tagInfo in $this.TagsInRangeWithHead) {
      [string]$until = $tagInfo.Label; 
      [PSCustomObject]$rangeInfo = $this.getRange($tagInfo, $this.AllTagsWithHead);

      # Attach an auxiliary Info field for later use
      #
      [array]$inRange = $this.SourceControl.ReadGitCommitsInRange(
        $format, $rangeInfo.Range, $header, $delim
      ) | ForEach-Object {
        Add-Member -InputObject $_ -NotePropertyName 'Info' -NotePropertyValue $null -PassThru;
      };

      $this.handleTagsInRange($releases, $until, $inRange);
    }

    return $releases;
  } # processCommits

  # $current is until and $from is synthetically set to the previous tag in sequence
  # tags in range eg:
  # |<-- most recent                                         oldest -->|
  #     0,     1,     2,     3,     4,     5,     6,     7,     8,     9
  #  HEAD, 3.0.2, 3.0.1, 3.0.0, 2.0.0, 1.2.0, 1.1.1, 1.1.0, 1.0.1, 1.0.0
  #                       curr,  from
  #
  # ASSUMPTION: descending
  #
  [PSCustomObject] getRange ([PSCustomObject]$current, [PSCustomObject[]]$allTags) {
    [System.Predicate[PSCustomObject]]$isCurrent = [System.Predicate[PSCustomObject]] {
      param(
        [PSCustomObject]$item
      )
      $item.Label -eq $current.Label;
    }
    [int]$indexOfCurrent = [Array]::FindIndex($allTags, $isCurrent);
    [boolean]$isOldest = $indexOfCurrent -eq ($allTags.Count - 1);
    
    [PSCustomObject]$result = if ($current.Label -eq 'HEAD') {
      [string]$latest = ($allTags.Count -gt 1) ? $allTags[1].Label : 'HEAD';

      [PSCustomObject]@{
        Range = ($latest -eq 'HEAD') ? 'HEAD' : "$($latest)..HEAD";
        From  = $latest;
        Until = 'HEAD';
      }
    }
    elseif ($isOldest) {
      [PSCustomObject]@{
        Range = $current.Label;
        From  = [string]::Empty;
        Until = $current.Label;
      }
    }
    else {
      [string]$from = $allTags[$indexOfCurrent + 1].Label;

      [PSCustomObject]@{
        Range = "$($from)..$($current.Label)";
        From  = $from;
        Until = $current.Label;
      }
    }

    return $result;
  }

  [void] handleTagsInRange ([hashtable]$releases, [string]$until, [array]$inRange) {
    foreach ($com in $inRange) {
      [string]$displayDate = $com.Date.ToString('yyyy-MM-dd - HH:mm:ss');
      Write-Debug "    ---> Label: '$until' PRE-FILTERED COUNT: '$($inRange.Count)' <---";
      Write-Debug "      + '$($com.Subject)', DATE: '$($displayDate)'";
      Write-Debug "    --------------------------";
      Write-Debug "";
    }

    [PSCustomObject]$squashed = $this.filterAndSquashCommits($inRange, $until);

    if ($squashed) {
      $releases[$until] = $squashed;
    }
  }

  # Filter and squash commits for a single release denoted by the Until label.
  # Returns a PSCustomObject instance with members:
  # - Squashed: hash indexed by issue no
  # - Commits: array of commits (no issue number, or squash not enabled)
  # - Label: until tag label for the release
  # - Dirty: array of unfiltered commits; release contains commits all filtered out.
  #
  # Returns: [PSTypeName('PoShLog.SquashedRelease')]
  #
  [PSCustomObject] filterAndSquashCommits([array]$commitsInRange, [string]$untilLabel) {
    [array]$filtered = $this.filter($commitsInRange, $untilLabel);
    [PSCustomObject]$result = if ($this._squashRegex) {

      [System.Collections.Generic.List[PSCustomObject]]$commitsWithoutIssueNo = `
        [System.Collections.Generic.List[PSCustomObject]]::new();

      [hashtable]$squashedHash = [ordered]@{}

      foreach ($commit in $filtered) {
        [System.Text.RegularExpressions.MatchCollection]$mc = $this._squashRegex.Matches(
          $commit.Subject
        );

        if ($mc.Count -gt 0) {
          [string]$issue = $mc[0].Groups['issue'];

          if ($squashedHash.ContainsKey($issue)) {
            $squashedItem = $squashedHash[$issue];
            $commit | Add-Member -NotePropertyName 'IsSquashed' -NotePropertyValue $true;

            # Do squash
            #
            if ($squashedItem -is [System.Collections.Generic.List[PSCustomObject]]) {
              $squashedItem.Add($commit); # => 3rd or more commit with this issue no
            }
            else {
              [System.Collections.Generic.List[PSCustomObject]]$newSquashedGroup = `
                [System.Collections.Generic.List[PSCustomObject]]::new();
              $squashedItem | Add-Member -NotePropertyName 'IsSquashed' -NotePropertyValue $true;
              $newSquashedGroup.Add($squashedItem); # => pre-existing first
              $newSquashedGroup.Add($commit); # => second commit
              $squashedHash[$issue] = $newSquashedGroup;
            }
          }
          else {
            $squashedHash[$issue] = $commit; # => first commit with this issue no
          }
        }
        else {
          if (($this.Options.Selection)?.IncludeMissingIssue -and
            $this.Options.Selection.IncludeMissingIssue) {
            $commitsWithoutIssueNo.Add($commit);
          }
        }
      }
      [PSCustomObject]$release = [PSCustomObject]@{
        PSTypeName = 'PoShLog.SquashedRelease';
        Squashed   = $squashedHash;
        Commits    = $commitsWithoutIssueNo;
        Label      = $untilLabel;
      }
      $release;
    }
    else {
      [PSCustomObject]$release = [PSCustomObject]@{
        PSTypeName = 'PoShLog.SquashedRelease';
        Commits    = $filtered;
        Label      = $untilLabel;
      }
      $release;
    }

    [boolean]$noSquashed = -not($result.Squashed) `
      -or ($result.Squashed -and ($result.Squashed.PSBase.Count -eq 0));

    [boolean]$noCommits = -not($result.Commits) `
      -or ($result.Commits -and ($result.Commits.Count -eq 0));

    if ($noSquashed -and $noCommits) {
      # No commits for release
      #
      $result = [PSCustomObject]@{
        PSTypeName = 'PoShLog.SquashedRelease';
        Dirty      = $commitsInRange;
        Label      = $untilLabel;
      };
    }

    return $result;
  } # filterAndSquashCommits

  [array] filter([array]$commits, [string]$untilLabel) {

    [regex[]]$includes = $this._grouper.BuildIncludes();
    [regex[]]$excludes = $this._grouper.BuildExcludes();

    [array]$filtered = $commits;

    if (($this.Options.Selection.Subject)?.Include) {
      $filtered = ($filtered | Where-Object {
          $this._grouper.TestMatchesAny($_.Subject, $includes);
        });    
    }

    if ($filtered) {
      $filtered = ($filtered | Where-Object {
          -not($this._grouper.TestMatchesAny($_.Subject, $excludes));
        });
    }

    if (-not($filtered)) {
      $filtered = @();
      Write-Debug "!!! Release: '$untilLabel'; no commits";
    }
    return $filtered;
  } # filter
} # PoShLog

# === [ GroupBy ] ==============================================================
#

class GroupBy {
  [void] SetDescending([boolean]$value) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExcludes)');
  }

  [boolean] TestMatchesAny([string]$subject, [regex[]]$expressions) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.TestMatchesAny)');
  } # TestMatchesAny

  [regex[]] BuildExpressions([string[]]$expressions) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExpressions)');
  } # BuildExpressions

  [regex[]] BuildIncludes() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildIncludes)');
  } # BuildIncludes

  [regex[]] BuildExcludes() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExcludes)');
  } # BuildExcludes

  [PSCustomObject[]] Partition(
    [hashtable]$releases, [string[]]$expressions, [PSCustomObject[]]$sortedTags) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.Partition)');
  } # Partition

  [void] Walk([PSCustomObject]$partitionedRelease, [PSCustomObject]$handlers, [PSCustomObject]$custom) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.Walk)');
  } # Walk
}

# === [ GroupByImpl ] ==========================================================
#
class GroupByImpl : GroupBy {
  [PSCustomObject]$Options;
  [boolean]$IsDescending = $true;
  hidden [string[]]$_segments;
  hidden [string]$_leafSegment;
  hidden [string]$_prefix = "partitions:";
  hidden [string]$_uncategorised = "uncategorised";
  hidden [string]$_dirty = "dirty";

  GroupByImpl([PSCustomObject]$options) {
    $this.Options = $options;
    $this._segments = -not([string]::IsNullOrEmpty($this.Options.Output.GroupBy)) ? `
      $this.Options.Output.GroupBy -split '/' : @('ungrouped');

    $this._leafSegment = ($this._segments.Count -gt 0) ? $this._segments[-1] : [string]::Empty;
  } # ctor

  [void] SetDescending([boolean]$value) {
    $this.IsDescending = $value;
  }

  [boolean] TestMatchesAny([string]$subject, [regex[]]$expressions) {
    return ($null -ne $this.GetMatchingRegex($subject, $expressions));
  } # TestMatchesAny

  [regex[]] BuildExpressions ([string[]]$expressions) {
    [regex[]]$result = foreach ($expr in $expressions) {
      [regex]::new($expr);
    }
    return $result;
  } # BuildExpressions

  [regex[]] BuildIncludes() {
    return $this.BuildExpressions(
      ($this.Options.Selection.Subject.Include -is [array]) ? `
        $this.Options.Selection.Subject.Include : @($this.Options.Selection.Subject.Include)
    );
  } # BuildIncludes

  [regex[]] BuildExcludes() {
    return $this.BuildExpressions(
      ($this.Options.Selection.Subject.Exclude -is [array]) ? `
        $this.Options.Selection.Subject.Exclude : @($this.Options.Selection.Subject.Exclude)
    );
  } # BuildExcludes

  [regex] GetMatchingRegex([string]$subject, [regex[]]$expressions) {
    [regex]$matched = $null;
    [int]$current = 0;

    while (-not($matched) -and ($current -lt $expressions.Count)) {
      [regex]$filterRegex = $expressions[$current];
      if ($filterRegex.IsMatch($subject)) {
        $matched = $filterRegex;
      }
      $current++;
    }

    return $matched;
  } # GetMatchingRegex

  # Resolves a path to a leaf. The leaf represents the bucket of commits resolved
  # to from the path.
  #
  # $segmentInfo: [PSTypeName('PoShLog.SegmentInfo')]
  # $partitionedRelease: [PSTypeName('PoShLog.PartitionedRelease')]
  # $handlers: [PSTypeName('PoShLog.Handler')]
  # $custom: [PSTypeName('PoShLog.WalkInfo')]
  #
  [PSCustomObject[]] resolve(
    [PSCustomObject]$segmentInfo,
    [PSCustomObject]$partitionedRelease,
    [PSCustomObject]$handlers,
    [PSCustomObject]$custom) {

    [PSCustomObject]$tagInfo = $partitionedRelease.Tag;
    [hashtable]$partitions = $partitionedRelease.Partitions;

    [PSCustomObject[]]$commits = if ($segmentInfo.Legs.Count -gt 0) {
      $pointer = $partitions;

      [int]$current = 0;
      foreach ($leg in $segmentInfo.Legs) {
        # 0: H3, 1: H4, 2: H5, 3: H6
        #
        if ($current -le 3) {
          [string]$headingNumeral = $("H$($current + 3)");

          $segmentInfo.ActiveSegment = $this._segments[$current];
          $segmentInfo.ActiveLeg = [string]::IsNullOrWhiteSpace($leg) ? $this._uncategorised : $leg;
          $handlers.OnHeading(
            $headingNumeral, $this.Options.Output.Headings.$headingNumeral,
            $segmentInfo, $tagInfo, $handlers.Utils, $custom
          );
          $segmentInfo.ActiveSegment = [string]::Empty;
          $segmentInfo.ActiveLeg = [string]::Empty;
        }

        $pointer = $pointer[$leg];
        $current++;
      }

      if (-not($pointer -is [System.Collections.Generic.List[PSCustomObject]])) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          "GroupByImpl.Resolve: failed to resolve path: '$($segmentInfo.Path)' to commits");
      }
      $pointer;
    }
    else {
      # Uncategorised commits go under a H3
      #
      $partitions[$this._uncategorised];
    }

    return $commits;
  } # resolve

  # Returns: [PSTypeName('PoShLog.SegmentInfo')]
  #
  [PSCustomObject] createSegmentInfo([string]$path) {
    [string[]]$legs = ($path -split '/') | Where-Object { $_ -ne $this._prefix; }

    [int]$legIndex = 0;
    [System.Collections.Generic.List[string]]$decoratedSegments = `
      [System.Collections.Generic.List[string]]::new();
    [hashtable]$segmentToLeg = @{}

    $legs | ForEach-Object {
      [string]$segment = $this._segments[$legIndex];
      $decoratedSegments.Add("$($segment):$_");
      $segmentToLeg[$segment] = $_;

      $legIndex++;
    }
    [string]$decoratedPath = $decoratedSegments -join '/';

    [PSCustomObject]$segmentInfo = [PSCustomObject]@{
      PSTypeName    = 'PoShLog.SegmentInfo';
      Path          = $path;
      Legs          = $legs;
      DecoratedPath = $decoratedPath;
      ActiveSegment = [string]::Empty;
      ActiveLeg     = [string]::Empty;
      IsDirty       = $false;
    }

    $this._segments | ForEach-Object {
      $segmentInfo | Add-Member -NotePropertyName $_ -NotePropertyValue $segmentToLeg[$_];
    }

    return $segmentInfo;
  } # createSegmentInfo

  # A partitioned release contains Partitions and Tag members
  #
  # $partitionedRelease: [PSTypeName('PoShLog.PartitionedRelease')]
  # $handlers: [PSTypeName('PoShLog.Handlers')]
  # $custom: [PSTypeName('PoShLog.WalkInfo')]
  #
  [void] Walk(
    [PSCustomObject]$partitionedRelease,
    [PSCustomObject]$handlers,
    [PSCustomObject]$custom) {

    [PSCustomObject]$tagInfo = $partitionedRelease.Tag;
    [hashtable]$partitions = $partitionedRelease.Partitions;
    [string[]]$paths = $partitionedRelease.Paths;
    [int]$cleanCount = 0;

    # named partitions first
    #
    foreach ($path in $paths) {
      [PSCustomObject]$segmentInfo = $this.createSegmentInfo($path);
      [PSCustomObject[]]$bucket = $this.resolve(
        $segmentInfo, $partitionedRelease, $handlers, $custom
      );

      foreach ($commit in $bucket) {
        # Sort the commits first?
        $handlers.OnCommit(
          $segmentInfo, $commit, $tagInfo, $handlers.Utils, $custom
        );
        $cleanCount++;
      }

      [PSCustomObject]$segmentInfo = [PSCustomObject]@{
        PSTypeName    = 'PoShLog.SegmentInfo';
        #
        Path          = [string]::Empty;
        DecoratedPath = [string]::Empty;
        IsDirty       = $false;
      }
      $handlers.OnEndBucket($segmentInfo, $tagInfo, $handlers.Utils, $custom);
    }

    if (($cleanCount -eq 0) -and $partitions.ContainsKey($this._dirty)) {
      [PSCustomObject]$segmentInfo = [PSCustomObject]@{
        PSTypeName    = 'PoShLog.SegmentInfo';
        #
        Path          = [string]::Empty;
        DecoratedPath = [string]::Empty;
        IsDirty       = $true;
      }
      $handlers.OnHeading(
        'Dirty', $this.Options.Output.Headings.Dirty,
        $segmentInfo, $tagInfo, $handlers.Utils, $custom
      );

      [PSCustomObject]$dirtyCommit = $partitions[$this._dirty][0];
      $handlers.OnCommit(
        $segmentInfo, $dirtyCommit, $tagInfo, $handlers.Utils, $custom
      );

      $handlers.OnEndBucket(
        $segmentInfo, $tagInfo, $handlers.Utils, $custom
      );
    }
  } # Walk

  # To generate the output, we need the releases to be in descending order of
  # the date, but of course, we need to be able to identify each release. Building
  # a hash of release tag to the release collection will not guarantee the order
  # if it's in a hash. So, we need an array. Partition will return an array of
  # PSCustomObjects containing fields: Tag, Partitions and Paths.
  #
  # $sortedTags: [PSTypeName('PoShLog.TagInfo')]
  #
  # Returns: [PSTypeName('PoShLog.PartitionedRelease')][array]
  #
  [PSCustomObject[]] Partition([hashtable]$releases, [PSCustomObject[]]$sortedTags) {

    [regex[]]$expressions = $this.BuildIncludes();
    [System.Collections.Generic.List[PSCustomObject]]$partitioned = `
      [System.Collections.Generic.List[PSCustomObject]]::new();

    [regex]$changeRegex = if ($this.Options.Selection.Subject?.Change -and
      -not([string]::IsNullOrEmpty($this.Options.Selection.Subject.Change))) {
      [regex]::new($this.Options.Selection.Subject.Change);
    }
    else {
      $null;
    }

    [PSCustomObject]$changeTypes = [GeneratorUtils]::CreateIsaLookup(
      'ChangeTypes', $this.Options.Output.Lookup.ChangeTypes
    );
    [PSCustomObject]$scopes = [GeneratorUtils]::CreateIsaLookup(
      'Scopes', $this.Options.Output.Lookup.Scopes
    );
    [PSCustomObject]$types = [GeneratorUtils]::CreateIsaLookup(
      'Types', $this.Options.Output.Lookup.Types
    );

    foreach ($tag in $sortedTags) {
      if ($releases.ContainsKey($tag.Label)) {
        [PSCustomObject]$release = $releases[$tag.Label];
        [PSCustomObject[]]$commits = $this.flatten($release);

        [hashtable]$partitions = @{}
        $pointer = $partitions;

        [System.Collections.Generic.List[string]]$paths = `
          [System.Collections.Generic.List[string]]::new();

        if ($this._segments.Count -eq 0) {
          $partitions[$this._uncategorised] = $commits;
        }
        else {
          Write-Debug "--->>> Partition for release '$($tag.Label)':";

          foreach ($com in $commits) {
            [regex]$partitionRegex = $this.GetMatchingRegex($com.Subject, $expressions);

            if (-not($partitionRegex)) {
              throw [System.Management.Automation.MethodInvocationException]::new(
                "GroupByImpl.Partition: (TAG: '$($tag.Label)') " +
                "internal logic error; commit: '$($com.Subject)' does not match");
            }

            [hashtable]$selectors = @{}
            [System.Text.RegularExpressions.MatchCollection]$mc = $partitionRegex.Matches($com.Subject);
            [System.Text.RegularExpressions.GroupCollection]$groups = $mc[0].Groups;

            [PoShLogProfile]::GetSegments($this._segments) | ForEach-Object {
              if ($groups.ContainsKey($_) ) {
                # IMPORTANT: a value must be allowed to be left to be the empty string. Do
                # NOT attempt to assign to some default like 'uncategorised' otherwise
                # this will break condition statements.
                #
                [string]$capture = $groups[$_].Success ? $groups[$_].Value : [string]::Empty;
                $selectors[$_] = if ($_ -eq 'break') {
                  # Exception override for break, the '!' is not a very useful
                  # value, so translate to something more explicit.
                  #
                  [PoShLogProfile]::BreakingValue($capture)
                }
                elseif ($_ -eq 'scope') {
                  $scopes.Isa.ContainsKey($capture) ? $scopes.Isa[$capture] : $capture;
                }
                elseif ($_ -eq 'type') {
                  $types.Isa.ContainsKey($capture) ? $types.Isa[$capture] : $capture;
                }
                elseif ($_ -eq 'change') {
                  $changeTypes.Isa.ContainsKey($capture) ? $changeTypes.Isa[$capture] : $capture;
                }
                else {
                  $capture;
                }
              }
            }

            if (-not($groups.ContainsKey('change')) -and ($null -ne $changeRegex)) {
              if ($groups.ContainsKey('body') -and $groups['body'].Success) {
                [string]$body = $groups['body'].Value;

                if ($changeRegex.IsMatch($body)) {
                  [string]$change = $changeRegex.Matches($body)[0].Value.Trim().ToLower();
                  $selectors['change'] = $changeTypes.Isa.ContainsKey($change) ? `
                    $changeTypes.Isa[$change] : [string]::Empty
                }
              }
            }

            $com.Info = [PSCustomObject]@{
              PSTypeName = 'PoShLog.CommitInfo';
              Selectors  = $selectors;
              IsBreaking = $($groups.ContainsKey('break') -and $groups['break'].Success);
              Groups     = $groups;
            }

            # $pointer can point to either a hashtable or a List. If it currently points
            # to a hashtable, then we're only part way through the groupBy path. If pointer
            # points to a List, then we have reached the end of the path, the leaf. When
            # we reach the leaf, we have found where we need to add the commit to. So
            # we end up with multiple layers of hashes, where the leaf elements of the hashes
            # is an array of commits (bucket). All commits in the same bucket, possess
            # the same set of characteristics defined by the groupBy path.
            #
            [string]$path = $this._prefix;
            foreach ($segment in $this._segments) {
              # Set the selector from the commit fields
              #
              [string]$selector = if ($selectors.ContainsKey($segment)) {
                $selectors[$segment];
              }
              else {
                $this._uncategorised;
              }
              $path += "/$selector";

              if (-not($pointer.ContainsKey($selector))) {
                $pointer[$selector] = ($segment -eq $this._leafSegment) ? `
                  [System.Collections.Generic.List[PSCustomObject]]::new() : @{};
              }
              $pointer = $pointer[$selector];
            } # foreach ($segment in $this._segments)

            if ($pointer -is [System.Collections.Generic.List[PSCustomObject]]) {
              Write-Debug "    ~ '$path' Adding commit '$($com.Subject)'";
              $paths.Add($path);
              $pointer.Add($com);
            }
            else {
              throw "something went wrong, reached leaf, but is not a list '$($pointer)'"
            }
            $pointer = $partitions;
          } # foreach ($com in $commits)

          if (($commits.Count -eq 0) -and ($release)?.Dirty) {
            $partitions[$this._dirty] = $release.Dirty;
          }
        }

        # Since the commits have been flattened, it no longer reflects the buckets. This means
        # that when $paths is added to, commits may be multiple counted, because the same path
        # within a release could be added more than once.
        #
        $paths = $($paths | Sort-Object | Get-Unique);

        $partitionItem = [PSCustomObject]@{
          PSTypeName = 'PoShLog.PartitionedRelease';
          Tag        = $tag;
          Partitions = $partitions;
          Paths      = $paths;
        }
        $partitioned.Add($partitionItem);

        if (($commits.Count -eq 0) -and ($release)?.Dirty) {
          Write-Debug "!!! Found '$($release.Dirty.Count)' DIRTY commits for release: '$($release.Label)'"
        }
      } # if ($releases.ContainsKey($tag.Label))
    } # foreach ($tag in $sortedTags)

    return $partitioned;
  } # Partition

  # $squashedRelease: [PSTypeName('PoShLog.SquashedRelease')]
  #
  # Returns: [PSTypeName('PoShLog.CommitInfo')][array]
  #
  [PSCustomObject[]] flatten([PSCustomObject]$squashedRelease) {

    [boolean]$selectLast = ($this.Options.Selection)?.Last -and $this.Options.Selection.Last;

    [System.Collections.Generic.List[PSCustomObject]]$squashed = `
      [System.Collections.Generic.List[PSCustomObject]]::new();

    if (($squashedRelease)?.Squashed -and $squashedRelease.Squashed.PSBase.Count -gt 0) {
      [string[]]$issues = $squashedRelease.Squashed.PSBase.Keys;

      foreach ($issue in $issues) {
        $item = $squashedRelease.Squashed[$issue];

        if ($item -is [PSCustomObject]) {
          $squashed.Add($item);
        }
        elseif ($item -is [System.Collections.Generic.List[PSCustomObject]]) {
          $squashed.Add($selectLast ? $item[-1] : $item[0]);
        }
        else {
          throw [System.Management.Automation.MethodInvocationException]::new(
            $(
              "GroupByImpl.flatten: found bad squashed item of type " +
              "$($item.GetType()) for release: '$($squashedRelease.Label)'"
            )
          );
        }
      }
    }

    [PSCustomObject[]]$others = (($squashedRelease)?.Commits -and $squashedRelease.Commits.Count -gt 0) `
      ? $squashedRelease.Commits : @();

    [PSCustomObject[]]$flattened = $squashed + $others;

    return $flattened;
  } # flatten

  # The resultant array is designed only to be iterated, we don't need direct access to
  # each release
  #
  [PSCustomObject[]] SortReleasesByDate([hashtable]$releases, [PSCustomObject[]]$sortedTags) {

    [PSCustomObject[]]$sorted = foreach ($tagInfo in $sortedTags) {
      if ($releases.ContainsKey($tagInfo.Label)) {
        $releases[$tagInfo.Label]
      }
    }

    return $sorted;
  } # SortReleasesByDate

  [int[]] CountCommits([PSCustomObject[]]$sortedReleases) {
    [int]$squashed = -1;
    [int]$all = -1;

    foreach ($release in $sortedReleases) {
      if (($release)?.Commits) {
        $all += $release.Commits;
        $squashed += $release.Commits;
      }

      if (($release)?.Squashed) {
        $all += $release.Squashed.PSBase.Count;
        $squashed++;
      }
    }
    return $squashed, $all;
  } # CountCommits
} # GroupByImpl

# === [ PoShLogGenerator ] ===================================================
#
class PoShLogGenerator {
  [PSCustomObject]$Options;
  [SourceControl]$_sourceControl;
  [GroupBy]$_grouper;
  [string]$_baseUrl;

  PoShLogGenerator([PSCustomObject]$options, [SourceControl]$sourceControl, [GroupBy]$grouper) {
    $this.Options = $options;
    $this._sourceControl = $sourceControl;
    $this._grouper = $grouper;
    $this._baseUrl = $this._sourceControl.ReadRemoteUrl();
  }

  [void] SetDescending([boolean]$value) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (PoShLogGenerator.SetDescending)');
  }

  [string] Generate([PSCustomObject[]]$releases, [object]$template, [PSCustomObject[]]$tagsInRange) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (PoShLogGenerator.Generate)');
  }
}

# === [ MarkdownPoShLogGenerator ] ===========================================
#
class MarkdownPoShLogGenerator : PoShLogGenerator {
  [GeneratorUtils]$_utils;
  [boolean]$IsDescending = $true;

  MarkdownPoShLogGenerator(
    [PSCustomObject]$options, [SourceControl]$sourceControl, [GroupBy]$grouper
  ): base ($options, $sourceControl, $grouper) {

    [PSCustomObject]$generatorInfo = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorInfo';
      #
      BaseUrl    = $this._baseUrl;
    }
    $this._utils = [GeneratorUtils]::new($options, $generatorInfo);
  } #ctor

  [void] SetDescending([boolean]$value) {
    $this.IsDescending = $value;
  }

  [string] Generate([PSCustomObject[]]$releases, [object]$template, [PSCustomObject[]]$tagsInRange) {
    [LineAppender]$appender = [LineAppender]::new();

    [scriptblock]$OnCommit = {
      param(
        [System.Management.Automation.PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('PoShLog.CommitInfo')]$commit,
        [System.Management.Automation.PSTypeName('PoShLog.TagInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$custom
      )
      [PSCustomObject]$output = $custom.Options.Output;

      [string]$commitStmt = $segmentInfo.IsDirty ? $output.Statements.DirtyCommit: $output.Statements.Commit;
      [hashtable]$commitVariables = $utils.GetCommitVariables($commit, $tagInfo);
      [string]$commitLine = $utils.Evaluate($commitStmt, $commit, $commitVariables);
      $commitLine = $utils.SpacesRegex.Replace($commitLine, ' ');

      $custom.Appender.AppendLine($commitLine);
    } # OnCommit

    [scriptblock]$OnEndBucket = {
      param(
        [System.Management.Automation.PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('PoShLog.TagInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$custom
      )
      [PSCustomObject]$output = $custom.Options.Output;

      if (${output}?.Literals.BucketEnd -and -not([string]::IsNullOrEmpty($output.Literals.BucketEnd))) {
        $custom.Appender.AppendLine([string]::Empty);
        $custom.Appender.AppendLine($output.Literals.BucketEnd);
      }
    } # OnEndBucket

    [scriptblock]$OnHeading = {
      param(
        [string]$headingType,
        [string]$headingStmt,
        [System.Management.Automation.PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$custom
      )
      [string]$prefix = [GeneratorUtils]::HeadingPrefix($headingType);
      if (-not($headingStmt.StartsWith($prefix))) {
        $headingStmt = $prefix + $headingStmt;
      }
      [hashtable]$headingVariables = $utils.GetHeadingVariables($segmentInfo, $tagInfo);

      [PSCustomObject]$commit = $null;
      [string]$headingLine = $utils.Evaluate($headingStmt, $commit, $headingVariables).Trim();
      $headingLine = $utils.SpacesRegex.Replace($headingLine, ' ');

      Write-Debug "--> Heading('$headingType'): Eval: '$headingLine', Scope: '$($headingVariables['scope'])'";

      $custom.Appender.AppendLine([string]::Empty);
      $custom.Appender.AppendLine($headingLine);
      $custom.Appender.AppendLine([string]::Empty);
    } # OnHeading

    [scriptblock]$OnSection = {
      param(
        [string]$sectionName,
        [string]$titleStmt,
        [string[]]$content,
        [System.Management.Automation.PSTypeName('PoShLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('PoShLog.WalkInfo')]$custom
      )
      [PSCustomObject]$commit = $null;
      [hashtable]$headingVariables = $utils.GetHeadingVariables($segmentInfo, $tagInfo);
      [string]$title = $utils.Evaluate($titleStmt, $commit, $headingVariables).Trim();
      Write-Debug "--> Section('$sectionName'): Title: $title, Scope: '$($headingVariables['scope'])'";
      $custom.Appender.AppendLine($title);

      foreach ($stmt in $content) {
        [string]$entry = [string]$title = $utils.Evaluate($stmt, $commit, $headingVariables).Trim();
        $custom.Appender.AppendLine($entry);
      }
      $custom.Appender.AppendLine([string]::Empty);
    }

    [PSCustomObject]$handlers = [PSCustomObject]@{
      PSTypeName = 'PoShLog.Handlers';
      #
      Utils      = $this._utils;
    }

    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnHeading' -Value $($OnHeading);
    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnCommit' -Value $($OnCommit);
    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnEndBucket' -Value $($OnEndBucket);
    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnSection' -Value $($OnSection);

    [string]$releaseStmt = $this.Options.Output.Headings.H2;

    if (-not($releaseStmt.StartsWith('## '))) {
      $releaseStmt = '## ' + $releaseStmt;
    }

    [PSCustomObject]$customWalkInfo = [PSCustomObject]@{
      PSTypeName = 'PoShLog.WalkInfo';
      #
      Appender   = $appender;
      Options    = $this.Options;
    }
    $nullSegmentInfo = $null;

    foreach ($release in $releases) {
      $handlers.OnHeading(
        'H2', $this.Options.Output.Headings.H2,
        $nullSegmentInfo, $release.Tag, $handlers.Utils, $customWalkInfo
      );

      if (-not([string]::IsNullOrEmpty($this.Options.Output.Sections.Release.Highlights))) {
        $handlers.OnSection(
          'Highlights',
          $this.Options.Output.Sections.Release.Highlights,
          $this.Options.Output.Sections.Release.HighlightContent,
          $nullSegmentInfo,
          $release.Tag,
          $this._utils, $customWalkInfo);
      }

      $this._grouper.Walk($release, $handlers, $customWalkInfo);
    }

    [PSCustomObject[]]$linkTags = $this._utils.GetLinkTags(
      $tagsInRange, $this._sourceControl.AllTagsWithoutHead
    );
    [string]$linksContent = $this.CreateComparisonLinks($linkTags);
    [string]$warningsContent = $this.CreateDisabledWarnings();
    [string]$schemaVersionContent = $this.CreateSchemaVersion();

    [array]$constituents = @(
      @{ Name = 'links'; Content = $linksContent },
      @{ Name = 'schema-version'; Content = $schemaVersionContent },
      @{ Name = 'warnings'; Content = $warningsContent },
      @{ Name = 'content'; Content = $appender.ToString() }
    )
    [string]$markdown = $template;
    foreach ($const in $constituents) {
      $markdown = $markdown.replace(
        $([PoShLogProfile]::MD_CONTENT_FORMAT -f $const.Name), $const.Content
      );
    }

    return $markdown;
  } # Generate

  [string] CreateComparisonLinks([PSCustomObject[]]$tagsInRange) {
    [string]$baseUrl = $this._sourceControl.ReadRemoteUrl();
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new();

    if ($tagsInRange.Count -gt 1) {
      [PSCustomObject]$first, [PSCustomObject[]]$others = $tagsInRange;

      foreach ($second in $others) {
        [string]$name = [GeneratorUtils]::TagDisplayName($first.Label);
        $builder.AppendLine(
          "[$($name)]: $($baseUrl)/compare/$($second.Label)...$($first.Label)"
        );

        $first = $second;
      }
    }

    return $builder.ToString();
  }

  [string] CreateDisabledWarnings() {

    [hashtable]$disabled = $this.Options.Output?.Warnings?.Disable;

    [string]$content = if (($null -ne $disabled) -and $disabled.PSBase.Count -gt 0) {
      [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new();
      [string[]]$warningCodes = $disabled.Keys;
      [string]$markdownFormat = "<!-- MarkDownLint-disable {0} -->";

      if ($warningCodes.Count -eq 1) {
        [void]$builder.AppendLine(
          $($markdownFormat -f $warningCodes[0])
        );
      }
      else {
        [string]$last = $warningCodes[-1];
        [string[]]$others = $warningCodes[0..$($warningCodes.Count - 2)];

        foreach ($code in $others) {
          [void]$builder.AppendLine(
            $($markdownFormat -f $code)
          );
        }
        [void]$builder.Append(
          $($markdownFormat -f $last)
        );
      }
      
      $builder.ToString();
    }
    else {
      [string]::Empty;
    }
    return $content;
  }

  [string] CreateSchemaVersion() {
    return $("<!-- Elizium.Loopz PoShLog options json schema version '{0}' -->" -f [PoShLogProfile]::SCHEMA_VERSION);
  }
} # MarkdownPoShLogGenerator

# === [ PoShLogProfile ] ======================================================
#
# conditional -> ?{var;name}

class PoShLogProfile {
  static [string]$PREFIXES = '?!&^*+';
  static [regex]$FieldRegex = [regex]::new(
    "(?<prefix>[$([PoShLogProfile]::PREFIXES)])\{(?:(?<var>[\w\-]+);)?(?<symbol>[\w\-]+)(?:;(?<else>[\w\-]+))?\}"
  );
  static [string] Snippet([char]$prefix, [string]$symbol) {
    return "$($prefix){$($symbol)}";
  }

  static [string[]] GetSegments([string[]]$segments) {
    [string[]]$result = @('break', 'change', 'scope', 'type');
    if ($segments.Count -eq 1 -and $segments[0] -eq 'ungrouped') {
      $result += 'ungrouped';
    }

    return $result;
  }
  static [string] BreakingValue ([string]$value) {
    return [string]::IsNullOrEmpty($value) ? 'non-breaking' : 'breaking';
  }
  static [string]$LOOKUP_UNKNOWN = '?';

  static [string] StatementPlaceholder() {
    return [PoShLogProfile]::Snippet('*', '$');
  }
  static [string]$MD_CONTENT_FORMAT = "[[{0}]]";
  static [string]$TEMPLATE_FILENAME = "TEMPLATE.md";

  static [string]$OPTIONS_SCHEMA_FILENAME = 'posh-log.options.schema.json';
  static [string]$SCHEMA_VERSION = '1.0.0';

  static [string]$DIRECTORY = '.posh-log';
} # PoShLogProfile

# === [ GeneratorUtils ] =======================================================
#
class GeneratorUtils {
  [PSCustomObject]$Options;
  [PSCustomObject]$Output;
  [PSCustomObject]$GeneratorInfo;
  [regex]$SpacesRegex = [regex]::new('\s{2,}');

  static [hashtable]$_headings = @{
    'H2'    = '## ';
    'H3'    = '### ';
    'H4'    = '#### ';
    'H5'    = '##### ';
    'H6'    = '###### ';
    'Dirty' = '### ';
  };

  static [hashtable]$_lookups = @{
    '_A' = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorUtils.Lookup';
      Instance   = 'Authors';
      Variable   = 'author';
    };

    '_B' = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorUtils.Lookup';
      Instance   = 'BreakingStatus';
      Variable   = 'break';
    };

    '_C' = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorUtils.Lookup';
      Instance   = 'ChangeTypes';
      Variable   = 'change';
    };

    '_S' = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorUtils.Lookup';
      Instance   = 'Scopes';
      Variable   = 'scope';
    };

    '_T' = [PSCustomObject]@{
      PSTypeName = 'PoShLog.GeneratorUtils.Lookup';
      Instance   = 'Types';
      Variable   = 'type';
    };
  }

  GeneratorUtils([PSCustomObject]$options, [PSCustomObject]$generatorInfo) {
    $this.Options = $options;
    $this.Output = $options.Output;
    $this.GeneratorInfo = $generatorInfo;
  }

  static [string] ConditionalSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('?', $value)
  }

  static [string] ConditionalVariableSnippet([string]$var, [string]$value, [string]$else) {
    return [string]::IsNullOrEmpty($else) ? `
      [PoShLogProfile]::Snippet('?', "$($var);$($value)") : `
      [PoShLogProfile]::Snippet('?', "$($var);$($value);$($else)");
  }

  static [string] LiteralSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('!', $value)
  }

  static [string] LookupSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('&', $value)
  }

  static [string] NamedGroupRefSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('^', $value)
  }

  static [string] StatementSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('*', $value)
  }

  static [string] VariableSnippet([string]$value) {
    return [PoShLogProfile]::Snippet('+', $value)
  }

  static [string] HeadingPrefix([string]$headingType) {
    return [GeneratorUtils]::_headings.ContainsKey($headingType) ? `
      [GeneratorUtils]::_headings[$headingType] : [string]::Empty;
  }

  static [string] AnySnippetExpression($value) {
    [string]$escaped = [regex]::Escape("{$value}");
    return "(?:[$([PoShLogProfile]::PREFIXES)])$($escaped)";
  }

  static [string] TagDisplayName([string]$label) {
    return $($label -eq 'HEAD') ? 'Unreleased' : $label;
  }

  static [PSCustomObject] CreateIsaLookup([string]$name, [hashtable]$lookup) {
    [PSCustomObject]$result = @{
      Isa   = @{};
      Value = @{};
    }
    [regex]$isaRegex = [regex]::new('^isa\:(?<parent>[^:]+)$');

    $lookup.Keys | ForEach-Object {
      if ($isaRegex.IsMatch($lookup[$_])) {
        [System.Text.RegularExpressions.Match]$m = $isaRegex.Matches($lookup[$_])?[0];
        [string]$parent = ${m}?.Groups['parent'].Success ? `
          $m.Groups['parent'].Value.Trim() : [string]::Empty;

        if ($_ -eq $parent) {
          throw [System.Management.Automation.MethodInvocationException]::new(
            $(
              "GeneratorUtils.CreateIsaLookup: found invalid isa entry: '$_'" +
              ", refers to itself in '$name'."
            )
          );
        }

        if (-not($lookup.ContainsKey($parent))) {
          throw [System.Management.Automation.MethodInvocationException]::new(
            $(
              "GeneratorUtils.CreateIsaLookup: found invalid isa entry: '$_'" +
              ", '$parent' does not exist in '$name'."
            )
          );
        }

        if (-not([string]::IsNullOrEmpty($parent))) {
          $result.Isa[$_] = $parent;
          $result.Value[$_] = $lookup[$parent];
        }
      }
      else {
        $result.Isa[$_] = $_;
        $result.Value[$_] = $lookup[$_];
      }
    }

    return $result;
  }

  [string] AvatarImg([string]$username) {
    [string]$hostUrl = ($this.Options)?.SourceControl.HostUrl;
    [string]$size = ($this.Options)?.SourceControl.AvatarSize;
    [string]$imgElement = $(
      "<img title='$($username)' src='$($hostUrl)$($username).png?size=$($size)'>"
    );

    return $imgElement;
  }

  [string] CommitIdLink([PSCustomObject]$commit) {
    [string]$baseUrl = $this.GeneratorInfo.BaseUrl;
    [string]$fullHash = $commit.FullHash;

    [string]$link = $(
      "[$($commit.CommitId)]($($baseUrl)/commit/$fullHash)"
    );

    return $link;
  }

  [string] IssueLink([string]$issue) {
    [string]$baseUrl = $this.GeneratorInfo.BaseUrl;

    [string]$link = -not([string]::IsNullOrEmpty($baseUrl)) ? $(
      "[#$($issue)]($($baseUrl)/issues/$($issue))";
    ) : [string]::Empty;

    return $link;
  }

  [string] GetVariable([string]$name, [PSCustomObject]$commit, [hashtable]$variables) {
    [string]$result = if ($variables.ContainsKey($name)) {
      $variables[$name];
    }
    elseif (($null -ne $commit) -and ($null -ne $commit.Info) -and $commit.Info.Groups.ContainsKey($name)) {
      $commit.Info.Groups[$name].Value.Trim();
    }
    else {
      [string]::Empty;
    }

    return $result;
  }

  [string] GetStatement([string]$name, [PSCustomObject]$options, [hashtable]$variables) {

    [string]$result = if ($name.EndsWith('Stmt')) {
      $name = $name -replace 'Stmt';

      if (-not([string]::IsNullOrEmpty($options.Output.Statements?.$name))) {
        $options.Output.Statements.$name;
      }
      else {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "GeneratorUtils.get-statement: error in options file" +
            ", '$($name)' is not defined Statement"
          )
        );
      }
    }
    elseif (-not([string]::IsNullOrEmpty($options.Output.Literals?.$name))) {
      $options.Output.Literals.$name;
    }
    else {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "GeneratorUtils.get-statement: error in options file" +
          ", '$($name)' is not defined Literal"
        )
      );
    }

    return $result;
  }

  # generic conditional statement with else
  #
  [string] IfStatement(
    [string]$variable, [string]$stmt, [PSCustomObject]$commit,
    [hashtable]$variables, [string]$else, [string[]]$trail) {

    [string]$variableValue = $this.GetVariable($variable, $commit, $variables);
    [boolean]$affirmative = (-not([string]::IsNullOrEmpty($variableValue))) -and ($variableValue -ne 'false');

    [string]$result = if ($affirmative) {
      [string]$stmtValue = $this.GetStatement($stmt, $this.Options, $variables);
      $this.evaluateStmt($stmtValue, $commit, $variables, $trail);
    }
    else {
      if (-not([string]::IsNullOrEmpty($else))) {
        [string]$elseValue = $this.GetStatement($else, $this.Options, $variables);
        $this.Evaluate($elseValue, $commit, $variables);
      }
      else {
        [string]::Empty;
      }
    }

    return $result
  }

  # $segmentInfo can be null
  #
  [hashtable] GetHeadingVariables([PSCustomObject]$segmentInfo, [PSCustomObject]$tagInfo) {

    [string]$displayTag = [GeneratorUtils]::TagDisplayName($tagInfo.Label);
    [hashtable]$headingVariables = @{
      'date'        = $tagInfo.Date.ToString($this.Output.Literals.DateFormat);
      'display-tag' = $displayTag;
      'tag'         = $tagInfo.Label;
      'link'        = "[$displayTag]";
    }

    if ($null -ne $segmentInfo) {
      $headingVariables['active-leg'] = $segmentInfo.ActiveLeg;
      $headingVariables['active-segment'] = $segmentInfo.ActiveSegment;

      [PoShLogProfile]::GetSegments($this._segments) | ForEach-Object {
        if (${segmentInfo}?.$_) {
          $headingVariables[$_] = $segmentInfo.$_;
        }
      }
    }

    return $headingVariables;
  }

  [hashtable] GetCommitVariables([PSCustomObject]$commit, [PSCustomObject]$tagInfo) {

    [hashtable]$commitVariables = @{
      'author'        = $commit.Author;
      'avatar-img'    = $this.AvatarImg($commit.Author);
      'date'          = $commit.Date.ToString($this.Output.Literals.DateFormat);
      'display-tag'   = [GeneratorUtils]::TagDisplayName($tagInfo.Label);
      'is-breaking'   = $commit.Info.IsBreaking;
      'is-squashed'   = $commit.Info.IsSquashed;
      'subject'       = $commit.Subject;
      'tag'           = $tagInfo.Label;
      'commitid'      = $commit.CommitId;
      'commitid-link' = $this.CommitIdLink($commit);
    }

    if (${commit}.Info -and $commit.Info.Groups['issue'] -and
      $commit.Info.Groups['issue'].Success) {
      [string]$issue = $commit.Info.Groups['issue'].Value;

      $commitVariables['issue'] = $issue;
      $commitVariables['issue-link'] = $this.IssueLink($issue);
    }

    if (${commit}?.Info) {
      [PoShLogProfile]::GetSegments($this._segments) | ForEach-Object {
        if ($commit.Info.Selectors.ContainsKey($_)) {
          $commitVariables[$_] = $commit.Info.Selectors[$_];
        }
      }
    }

    return $commitVariables;
  } # GetCommitVariables

  # |<-- most recent                                         oldest -->|
  #     0,     1,     2,     3,     4,     5,     6,     7,     8,     9
  #  HEAD, 3.0.2, 3.0.1, 3.0.0, 2.0.0, 1.2.0, 1.1.1, 1.1.0, 1.0.1, 1.0.0
  #               |<-- in range  -->| (assuming in range = 2.0.0..3.0.1)
  #               last in range index = 4, so we add item with index 5
  #
  # If tags in range includes the oldest tag, then just return tagsInRange
  # otherwise we need to get 1 extra older tag from allTags and append
  # that to end of tagsInRange.
  #
  [PSCustomObject[]] GetLinkTags([PSCustomObject[]]$tagsInRange, [PSCustomObject[]]$allTags) {

    [PSCustomObject]$lastTagInRange = $tagsInRange[-1];
    [PSCustomObject]$oldestTag = $allTags[-1];

    [PSCustomObject[]]$linkTags = if ($lastTagInRange.Label -eq $oldestTag.Label) {
      @($tagsInRange);
    }
    else {
      [System.Predicate[PSCustomObject]]$predicate = [System.Predicate[PSCustomObject]] {
        param(
          [PSCustomObject]$item
        )
        $item.Label -eq $lastTagInRange.Label;
      }
      [int]$indexLastInRange = [Array]::FindIndex($allTags, $predicate);
      @($tagsInRange) + $allTags[$indexLastInRange + 1];
    }

    return $linkTags;
  }

  [string] Evaluate(
    [string]$source,
    [PSCustomObject]$commit,
    [hashtable]$variables) {

    [string[]]$trail = @();
    [string]$statement = $this.evaluateStmt($source, $commit, $variables, $trail);
    return $this.ClearUnresolvedFields($statement);
  } # Evaluate

  [string] evaluateStmt([string]$source,
    [PSCustomObject]$commit,
    [hashtable]$variables,
    [string[]]$trail) {

    [string]$result = if ([PoShLogProfile]::FieldRegex.IsMatch($source)) {
      [System.Text.RegularExpressions.MatchCollection]$mc = [PoShLogProfile]::FieldRegex.Matches($source);

      [string]$evolve = $source;
      foreach ($m in $mc) {
        [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

        if ($groups['prefix'].Success -and $groups['symbol'].Success) {
          [string]$prefix = $groups['prefix'].Value;
          [string]$symbol = $groups['symbol'].Value;

          if ($trail -notContains $symbol) {

            [string]$target, [string]$with = switch ($prefix) {
              '*' {
                [string]$snippet = $groups[0];
                $trail += $symbol;

                if ($evolve.Contains($snippet)) {
                  [string]$property = $symbol -replace 'Stmt';

                  if ($null -eq $this.Output.Statements?.$property) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      "GeneratorUtils.evaluateStmt(bad options config): " +
                      "'$($symbol)' is not a defined Statement");
                  }

                  [string]$statement = $this.Output.Statements.$property;
                  [string]$replacement = $this.evaluateStmt(
                    $statement, $commit, $variables, $trail
                  );

                  $snippet, $replacement
                }
                break;
              }

              '?' {
                [string]$variable = $groups['var'].Value;
                [string]$else = ($groups.ContainsKey('else')) ? $groups['else'].Value : [string]::Empty;
                [string]$snippet = $groups[0];
                $trail += $symbol;

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = $this.IfStatement(
                    $variable, $symbol, $commit, $variables, $else, $trail
                  );

                  # we need to recurse here just in-case the expansion has resulted in
                  # unresolved references.
                  #
                  if (-not([string]::IsNullOrEmpty($replacement))) {
                    $replacement = $this.evaluateStmt(
                      $replacement, $commit, $variables, $trail
                    );
                  }

                  $snippet, $replacement
                }
                break;
              }

              '!' {
                [string]$snippet = $groups[0];

                if ($evolve.Contains($snippet)) {
                  if ($null -eq ($this.Output.Literals)?.$symbol) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      "GeneratorUtils.evaluateStmt(bad options config): " +
                      "'$($symbol)' is not a defined Literal"
                    );
                  }
                  [string]$replacement = $this.Output.Literals.$symbol;
                  $snippet, $replacement
                }
                break;
              }

              '&' {
                [string]$snippet = $groups[0];

                if ($evolve.Contains($snippet)) {
                  if (-not([GeneratorUtils]::_lookups.ContainsKey($symbol))) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      $(
                        "GeneratorUtils.Evaluate(bad options config): " +
                        "Lookup '$symbol' not found"
                      )
                    );
                  }

                  [string]$instance = [GeneratorUtils]::_lookups[$symbol].Instance;
                  [string]$variable = [GeneratorUtils]::_lookups[$symbol].Variable;
                  [string]$seek = $variables[$variable];

                  [string]$replacement = (
                    $this.Output.Lookup.$instance.ContainsKey($seek)) ? `
                    $this.Output.Lookup.$instance[$seek] : $($this.Output.Lookup.$instance['?'] ?? [string]::Empty);

                  $snippet, $replacement
                }
                break;
              }

              '^' {
                [string]$snippet = $groups[0];

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = if (($commit)?.Info.Groups -and `
                      $commit.Info.Groups[$symbol].Success) {
                    $commit.Info.Groups[$symbol].Value.Trim();
                  }
                  else {
                    [string]::Empty;
                  }

                  $snippet, $replacement
                }
                break;
              }

              '+' {
                [string]$snippet = $groups[0];

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = ($variables.ContainsKey($symbol)) `
                    ? $variables[$symbol]: [string]::Empty;

                  $snippet, $replacement
                }
                break;
              }
            }
            $evolve = $evolve.Replace($target, $with);
          }
          else {
            throw [System.Management.Automation.MethodInvocationException]::new(
              $(
                "GeneratorUtils.Evaluate(bad options config): " +
                "statement: '$source' contains circular reference: '$symbol'"
              )
            );
          }
        }
        else {
          throw [System.Management.Automation.MethodInvocationException]::new(
            $(
              "GeneratorUtils.Evaluate(prefix/symbol): " +
              "statement: '$source' contains failed group references"
            )
          );
        }
      }
      $evolve;
    }
    else {
      $source;
    }

    return $result;
  } # evaluateStmt

  [string] ClearUnresolvedFields($value) {
    return [PoShLogProfile]::FieldRegex.Replace($value, '');
  }
} # GeneratorUtils

# === [ PoShLogOptionsManager ] ==============================================
#
class PoShLogOptionsManager {
  [PSCustomObject]$OptionsInfo;
  [boolean]$Found;
  [ProxyGit]$Proxy;

  PoShLogOptionsManager([ProxyGit]$proxy, [PSCustomObject]$optionsInfo) {

    $this.Proxy = $proxy;
    $this.OptionsInfo = $optionsInfo;
  }

  [void] Init() {
    [void]$this.IsValidGroupBy($this.OptionsInfo.GroupBy);
  }

  [string] ReadRootPath() {
    [string]$root = if (($this.OptionsInfo)?.Root -and `
        -not([string]::IsNullOrEmpty($this.OptionsInfo.Root))) {
      $this.OptionsInfo.Root
    }
    else {
      $this.Proxy.Root();
    }
    return $root;
  }

  [string] FileName([string]$name, [boolean]$ifEmoji) {
    return $ifEmoji ? $($name + '-emoji' + $this.OptionsInfo.Base) : $($name + $this.OptionsInfo.Base);
  }

  [string] FullPath([string]$name, [boolean]$ifEmoji) {
    [string]$directoryPath = $this.DirectoryPath()
    [string]$fileName = $this.FileName($name, $ifEmoji);
    [string]$withExtension = $fileName + '.json';
    [string]$fullPath = Join-Path -Path $directoryPath -ChildPath $withExtension;

    return $fullPath;
  }

  [string] DirectoryPath([string]$fileName) {
    [string]$directoryPath = $this.DirectoryPath();
    return Join-Path -Path $directoryPath $fileName; 
  }

  [string] DirectoryPath() {
    [string]$root = $this.ReadRootPath();
    [string]$directoryPath = Join-Path -Path $root -ChildPath $this.OptionsInfo.DirectoryName;
    return $directoryPath;
  }

  [string] EnsureRepoDirectoryPath() {
    [string]$directoryPath = $this.DirectoryPath();

    if (-not(Test-Path -LiteralPath $directoryPath)) {
      [void]$(New-Item -ItemType 'Directory' -Path $directoryPath);
    }

    return $directoryPath;
  }

  [PSCustomObject] Load([string]$name, [boolean]$ifEmoji) {
    [string]$fullPath = $this.FullPath($name, $ifEmoji);
    [PSCustomObject]$options = if (Test-Path -LiteralPath $fullPath) {
      [string]$json = Get-Content -LiteralPath $fullPath;
      [string]$schemaPath = Join-Path -Path $PSScriptRoot `
        -ChildPath $([PoShLogProfile]::OPTIONS_SCHEMA_FILENAME);
      $null = Test-Json -Json $json -SchemaFile $schemaPath;

      $temp = $($json | ConvertFrom-Json -Depth 20);
      $this.Init($temp);
    }

    return $options;
  }

  [PSCustomObject] Init([PSCustomObject]$options) {
    $options = $this.restoreTypes($options);
    $this.verify($options);

    3..6 | Foreach-Object {
      [string]$headingType = "H$($_)";
      [string]$injection = $this.injectSegment(
        $options.Output.Headings.$headingType, $headingType, $options.Output.GroupBy
      );
      $options.Output.Headings.$headingType = $injection;
    }

    return $options;
  }

  [PSCustomObject] Eject([string]$name, [boolean]$ifEmoji) {
    [PSCustomObject]$options = $this.NewOptions($name, $ifEmoji);
    $this.Save($name, $ifEmoji, $options);

    $options.Output.Template = $this.Template();
    return $options;
  }

  [void] Save([string]$name, [boolean]$ifEmoji, [PSCustomObject]$options) {
    [string]$fullPath = $this.FullPath($name, $ifEmoji);
    [string]$extension = [System.IO.Path]::GetExtension($fullPath);
    [string]$resolvedName = [System.IO.Path]::GetFileName($fullPath);
    [string]$withoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($resolvedName);
    [string]$testPath = $fullPath;
    [boolean]$verified = $false;
    [string]$alternate = [string]::Empty
    [int]$appendage = 0;

    do {
      if (Test-Path -LiteralPath $testPath) {
        $appendage++;
        $alternate = "$($withoutExtension)-{0:d2}$($extension)" -f $appendage;
        $testPath = $this.DirectoryPath($alternate);
      }
      else {
        $verified = $true;
      }
    } while (-not($verified));

    if (Test-Path -LiteralPath $fullPath) {
      Rename-Item -LiteralPath $fullPath `
        -NewName $([System.IO.Path]::GetFileName($testPath));
    }

    $content = $options | ConvertTo-Json -Depth 20;
    $this.EnsureRepoDirectoryPath();
    Set-Content -LiteralPath $fullPath -Value $content;
  }

  [object] Template() {
    [string]$templateName = [PoShLogProfile]::TEMPLATE_FILENAME;
    [string]$templatePath = $this.DirectoryPath($templateName);

    [object]$content = if (Test-Path -LiteralPath $templatePath) {
      Get-Content -LiteralPath $templatePath -Raw;
    }
    else {
      Set-Content -LiteralPath $templatePath -Value $([PoShLogOptionsManager]::DEFAULT_TEMPLATE);
      [PoShLogOptionsManager]::DEFAULT_TEMPLATE;
    }

    [string]$format = [PoShLogProfile]::MD_CONTENT_FORMAT;
    'warnings', 'content', 'links', 'schema-version' | Foreach-Object {
      if (-not($content.ToString().Contains($($format -f $_)))) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.Template: error in template file ($($templateName))" +
            ", missing '$($_)' placeholder"
          )
        );
      }
    }

    return $content;
  }

  [boolean] IsValidGroupBy([string]$groupBy) {
    [string[]]$segments = $groupBy -split '/';

    if ($segments.Count -gt 4) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        "GroupBy '$GroupBy' is invalid, can contain at most 4 segments");
    }

    [int]$uniqueCount = $($segments | Select-Object -Unique).Count;

    if ($uniqueCount -ne $segments.Count) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        "GroupBy '$GroupBy' is invalid, contains duplicate segments");
    }

    return $($null -eq ($segments | Where-Object {
          [PoShLogProfile]::GetSegments($this._segments) -notContains $_;
        }))
  }

  [PSCustomObject] FindOptions([string]$name, [boolean]$ifEmoji) {
    [PSCustomObject]$options = $this.Load($name, $ifEmoji);

    if ($null -eq $options) {
      $this.Found = $false;

      $options = $this.NewOptions($name, $ifEmoji);

      if ($null -ne $options) {
        $this.Save($name, $ifEmoji, $options);
      }
    }
    else {
      $this.Found = $true;
    }

    $options.Output.Template = $this.Template();
    return $options;
  }

  [PSCustomObject] NewOptions([string]$name, [boolean]$ifEmoji) {
    [string]$defaultHeadingStmt = [PoShLogProfile]::StatementPlaceholder();

    [PSCustomObject]$skeleton = [PSCustomObject]@{
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
      } # Snippet

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
          Include    = @(
            # feat(foo)!: Add new bar (#42)
            #
            $(
              '^(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
              '(?:\((?<scope>[\w]+)\))?(?<break>!)?:\s(?<body>[^\(]+)(?:\(?#(?<issue>\d{1,6})\)?)'
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
          );
          Exclude    = @();
        }

        Tags                = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Selection.Tags';
          #
          # FROM, commits that come after the TAG
          # UNTIL, commits up to and including TAG
          #
          # In these tests, there is no default, however, when we generate
          # the default config, the default here will be Until = 'HEAD',
          # which means get everything
          #
        }
      } # Selection

      SourceControl = [PSCustomObject]@{
        PSTypeName   = 'PoShLog.Options.SourceControl';
        #
        Service      = 'GitHub';
        HostUrl      = 'https://github.com/';
        AvatarSize   = '24';
        CommitIdSize = 7;
      } # SourceControl

      Output        = [PSCustomObject]@{
        PSTypeName = 'PoShLog.Options.Output';
        #
        # special variables:
        # -> &{_A} = author => indexes into the Authors hash
        # -> &{_B} = break => indexes into the BreakingStatus hash
        # -> &{_C} = change => indexes into the Change hash
        # -> &{_S} = scope => indexes into the Scopes hash if defined
        # -> &{_T} = type => indexes into the Types hash
        #
        Headings   = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Output.Headings';
          #
          H2         = 'Release [+{display-tag}] / +{date}';
          H3         = $defaultHeadingStmt;
          H4         = $defaultHeadingStmt;
          H5         = $defaultHeadingStmt;
          H6         = $defaultHeadingStmt;
          Dirty      = 'DIRTY: *{dirtyStmt}';
        }  # Headings

        Sections   = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Output.Sections';
          #
          Release    = [PSCustomObject]@{
            PSTypeName       = 'PoShLog.Options.Output.Sections.Release';
            #
            Highlights       = '*{highlightsStmt}';
            HighlightContent = @('', '*{highlightDummy}');
          }
        }

        GroupBy    = 'scope/type/change/break';

        LookUp     = [PSCustomObject]@{ # => '&'
          PSTypeName     = 'PoShLog.Options.Output.Lookup';
          #
          # => &{_A} ('_A' is a synonym of 'author')
          #
          Authors        = @{
            '?' = $this.useEmoji($ifEmoji, ':woman_office_worker:');
          }
          # => &{_B} ('_B' is a synonym of 'break')
          # In the regex, breaking change is indicated by ! (in accordance with
          # established wisdom) and this is translated into 'breaking', and if
          # missing, 'non-breaking', hence the following loop up keys.
          #
          BreakingStatus = @{
            'breaking'     = $this.useEmoji($ifEmoji, ':radioactive: BREAKING CHANGES', 'BREAKING CHANGES');
            'non-breaking' = $this.useEmoji($ifEmoji, ':recycle: NON BREAKING CHANGES', 'NON BREAKING CHANGES');
          }
          # => &{_C} ('_C' is a synonym of 'change')
          #
          ChangeTypes    = @{ # The first word in the commit subject after 'type(scope): '
            'Add'       = $this.useEmoji($ifEmoji, ':heavy_plus_sign:');
            'Change'    = $this.useEmoji($ifEmoji, ':o:');
            'Fixed'     = $this.useEmoji($ifEmoji, ':beetle:');
            'Deprecate' = $this.useEmoji($ifEmoji, ':heavy_multiplication_x:');
            'Remove'    = $this.useEmoji($ifEmoji, ':heavy_minus_sign:');
            'Secure'    = $this.useEmoji($ifEmoji, ':key:');
            'Update'    = $this.useEmoji($ifEmoji, 'isa:Change');
            '?'         = $this.useEmoji($ifEmoji, ':lock:');
          }

          # => &{_S} ('_S' is a synonym of 'scope')
          #
          Scopes         = @{
            # this is user defined. It should be maintained. Known scopes in
            # the project should be defined here
            #
            'all' = $this.useEmoji($ifEmoji, ':star:');
            '?'   = $this.useEmoji($ifEmoji, ':lock:');
          }

          # => &{_T} ('_T' is a synonym of 'type')
          # (These types must be consistent with includes regex)
          #
          Types          = @{
            'fix'   = $this.useEmoji($ifEmoji, ':heavy_check_mark:');
            'feat'  = $this.useEmoji($ifEmoji, ':gift:');
            'build' = $this.useEmoji($ifEmoji, ':hammer:');
            'chore' = $this.useEmoji($ifEmoji, ':nut_and_bolt:');
            'ci'    = $this.useEmoji($ifEmoji, ':trophy:');
            'doc'   = $this.useEmoji($ifEmoji, 'isa:docs');
            'docs'  = $this.useEmoji($ifEmoji, ':clipboard:');
            'style' = $this.useEmoji($ifEmoji, ':hotsprings:');
            'ref'   = $this.useEmoji($ifEmoji, ':gem:');
            'perf'  = $this.useEmoji($ifEmoji, ':rocket:');
            'test'  = $this.useEmoji($ifEmoji, ':test_tube:');
            '?'     = $this.useEmoji($ifEmoji, ':lock:');
          }
        } # Lookup

        Literals   = [PSCustomObject]@{ # => '!'
          PSTypeName    = 'PoShLog.Options.Output.Literals';
          #
          Broken        = $this.useEmoji($ifEmoji, ':warning:', 'break');
          BucketEnd     = '---';
          DateFormat    = 'yyyy-MM-dd';
          Dirty         = $this.useEmoji($ifEmoji, ':poop:', 'dirty');
          Uncategorised = 'uncategorised';
        } # Literals

        Statements = [PSCustomObject]@{ # => '*'
          PSTypeName     = 'PoShLog.Options.Output.Statements';
          #
          # These are overwritten but specified here as a reference to all
          # valid fields.
          #
          ActiveScope    = "+{scope}";
          Author         = ' by `@+{author}` &{_A}';
          Avatar         = ' by `@+{author}` +{avatar-img}';
          Break          = '&{_B}';
          Breaking       = '!{broken} *BREAKING CHANGE* ';
          Change         = 'Change Type(&{_C}+{change})';
          ChangeCommit   = '&{_C} ';
          Commit         = '+ ?{is-breaking;breakingStmt}?{is-squashed;squashedStmt}?{change;changeCommitStmt}*{subjectStmt}*{avatarStmt}*{metaStmt}';
          Dirty          = '!{dirty}';
          DirtyCommit    = '+ ?{is-breaking;breakingStmt}+{subject}';
          Highlights     = $this.useEmoji($ifEmoji, ':sparkles: HIGHLIGHTS', 'HIGHLIGHTS');
          HighlightDummy = '+ Lorem ipsum dolor sit amet';
          IssueLink      = ' \<**+{issue-link}**\>';
          Meta           = ' (Id: **+{commitid-link}**)?{issue-link;issueLinkStmt}';
          Scope          = 'Scope(&{_S}?{scope;activeScopeStmt;Uncategorised})';
          Squashed       = 'SQUASHED: ';
          Subject        = '**^{body}**';
          Type           = 'Commit Type(&{_T}+{type})';
          Ungrouped      = 'UNGROUPED';
        } # Statements

        Warnings   = [PSCustomObject]@{
          PSTypeName = 'PoShLog.Options.Output.Warnings';
          Disable    = @{
            'MD013' = 'line-length';
            'MD024' = 'no-duplicate-heading/no-duplicate-header';
            'MD026' = 'no-trailing-punctuation';
            'MD033' = 'no-inline-html';
          }
        } # Warnings

        Base       = 'ChangeLog';
        Template   = @();
      } # Output
    } # Skeleton options

    [PSCustomObject]$options = switch ($name) {
      'Alpha' {
        $skeleton.Output.Statements.Commit = $(
          "+ ?{scope;scopeCommitStmt}?{is-breaking;breakingStmt}?{is-squashed;squashedStmt}" +
          "?{change;changeCommitStmt}*{subjectStmt}?{issue-link;issueOnlyStmt}"
        );
        $skeleton.Output.Statements | Add-Member `
          -NotePropertyName 'ScopeCommit' -NotePropertyValue '***+{scope}***:';

        $skeleton.Output.Statements | Add-Member `
          -NotePropertyName 'IssueOnly' -NotePropertyValue '*{IssueLink}';
        $skeleton;

        break;
      }

      'Elizium' {
        $skeleton.Output.Statements.Commit = $(
          "+ ?{is-breaking;breakingStmt}?{is-squashed;squashedStmt}" +
          "?{change;changeCommitStmt}*{subjectStmt}*{avatarStmt}*{metaStmt}"
        );
        $skeleton.Selection | Add-Member `
          -NotePropertyName 'Change' -NotePropertyValue '^[\w]+'
        $skeleton;

        break;
      }

      'Test' {
        $skeleton.Output.Statements.Commit = $(
          "+ ?{is-breaking;breakingStmt}?{is-squashed;squashedStmt}" +
          "*{changeStmt}*{subjectStmt}*{authorStmt}*{metaStmt}"
        );
        $skeleton;

        break;
      }

      'Zen' {
        $skeleton.Output.Statements.Commit = $(
          "+ ?{is-breaking;breakingStmt}?{is-squashed;squashedStmt}" +
          "?{change;changeCommitStmt}*{subjectStmt}"
        );

        $skeleton;

        break;
      }

      default {
        $skeleton;
      }
    }

    return $options;
  } # NewOptions

  [string] useEmoji([boolean]$emojiRequired, [string]$emojiValue) {
    return $this.useEmoji($emojiRequired, $emojiValue, [string]::Empty);
  }

  [string] useEmoji([boolean]$emojiRequired, [string]$emojiValue, [string]$otherwise) {
    return $emojiRequired ? $emojiValue : $otherwise;
  }

  [string] injectSegment([string]$headingStatement, [string]$headingType, [string]$groupByValue) {
    return $this.injectSegment($headingStatement, $headingType, $groupByValue, 'NONE');
  }

  # eg headingStatement = 'HEADING: *{$}' => 'HEADING: *{scopeStmt}'
  #
  [string] injectSegment([string]$headingStatement, [string]$headingType,
    [string]$groupByValue, [string]$otherwise) {

    [string]$placeholder = [PoShLogProfile]::StatementPlaceholder();

    if (-not($headingStatement.Contains($placeholder))) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.restoreTypeName: error in options file" +
          ", header-$($headingType) ($headingStatement) is missing statement placeholder ($placeholder)"
        )
      );
    }

    [string[]]$segments = $groupByValue -split '/';

    # eg:
    # H3 = '*{scopeStmt}';
    # H4 = '*{typeStmt}';
    # H5 = '*{breakingStmt}'
    # H6 = '*{changeStmt}';
    #
    [string]$heading = if ($segments -and ($segments.Count -gt 0)) {
      if ($segments.Count -eq 1) {
        [PoShLogProfile]::Snippet('*', $($segments[0] + 'Stmt'));
      }
      else {
        # eg:
        # H3   /H4  /H5   /H6
        # scope/type/break/change
        #
        [int]$headingNumeral = [int]::Parse($headingType[1]);
        
        if ($headingNumeral -in 3..6) {
          [int]$index = $($headingNumeral - 3);

          if ($index -lt $segments.Count) {
            [PoShLogProfile]::Snippet(
              '*', $($segments[$($headingNumeral - 3)] + 'Stmt')
            );
          }
          else {
            $otherwise;
          }
        }
        else {
          $otherwise;
        }
      }
    }
    else {
      $otherwise;
    }
    
    return $headingStatement.Replace($placeholder, $heading);
  }

  [PSCustomObject] restoreTypes([PSCustomObject]$options) {
    # This is required because ConvertTo-Json/ConvertFrom-Json fails to preserve
    # the PSTypeName members.
    #
    $this.restoreTypeName($options, 'Options');
    $this.restoreTypeName(${options}?.Snippet, 'Options.Snippet');
    $this.restoreTypeName(${options}?.Snippet?.Prefix, 'Options.Snippet.Prefix');
    $this.restoreTypeName(${options}?.Selection, 'Options.Selection');
    $this.restoreTypeName(${options}?.Selection?.Tags, 'Options.Selection.Tags');
    $this.restoreTypeName(${options}?.SourceControl, 'Options.SourceControl');

    [PSCustomObject]$output = ($options)?.Output;
    if ($null -ne $output) {
      $this.restoreTypeName($output, 'Options.Output');
      $this.restoreTypeName(${output}?.Headings, 'Options.Output.Headings');
      $this.restoreTypeName(${output}?.Lookup, 'Options.Output.Lookup');
      $this.restoreTypeName(${output}?.Literals, 'Options.Output.Literals');
      $this.restoreTypeName(${output}?.Statements, 'Options.Output.Statements');
      $this.restoreTypeName(${output}?.Warnings, 'Options.Output.Warnings');
    }
    else {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.restoreTypes: error in options file" +
          ", missing 'Output' entry"
        )
      );
    }

    # Repair the hashtables
    #
    if (${output}?.Lookup -and (-not($output.Lookup -is [PSCustomObject]))) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.restoreTypes: error in options file" +
          ", Output.Lookup is not an object (type: '$($output.Lookup.GetType())')"
        )
      );
    }

    [PSCustomObject]$lookup = ${output}?.Lookup;
    $this.repairHashTable($lookup, 'Authors', $true);
    $this.repairHashTable($lookup, 'BreakingStatus', $false);
    $this.repairHashTable($lookup, 'ChangeTypes', $true);
    $this.repairHashTable($lookup, 'Scopes', $true);
    $this.repairHashTable($lookup, 'Types', $true);
    $this.repairHashTable(${output}?.Warnings, 'Disable', $false);

    return $options;
  }

  [void] restoreTypeName([object]$node, [string]$path) {
    try {
      if (-not($node -is [PSCustomObject])) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.restoreTypeName: error in options file" +
            ", item at path: '$path' is not an object"
          )
        );
      }

      if ($null -ne $node) {
        $node.PSObject.TypeNames.Insert(0, "PoShLog.$path");
      }
      else {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.restoreTypeName: error in options file" +
            ", missing entry at: '$path'"
          )
        );
      }
    }
    catch {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.restoreTypeName: failed to restore type for '$path'" +
          ", error in options file."
        )
      );
    }
  }

  [void] repairHashTable([object]$node, [string]$name, [boolean]$withDefaultCheck) {
    # This method is required because ConvertTo-Json/ConvertFrom-Json fails to preserve
    # hashtables. To be fair, there is no distinction between a hashtable and
    # PSCustomObject in JSON notation, so there is no way to know what type an entry should
    # be. Using -AsHashTable on ConvertFrom-Json is of no use because it not selective. It
    # would convert everything to hashtables which is not what we want. So we convert
    # individual entries manually ourself.
    #
    if ($null -ne $node) {
      if (-not($node -is [PSCustomObject])) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.restoreTypeName: error in options file" +
            ", item '$name' is not an object"
          )
        );
      }

      if ($node.$name -is [PSCustomObject]) {
        [PSCustomObject]$target = $node.$name;
        [hashtable]$hash = @{}

        foreach ($property in $target.psobject.properties.name) {
          $hash[$property] = $target.$property;
        }
        $node.$name = $hash;

        if ($withDefaultCheck) {
          if (-not($hash.ContainsKey([PoShLogProfile]::LOOKUP_UNKNOWN))) {
            throw [System.Management.Automation.MethodInvocationException]::new(
              $(
                "PoShLogOptionsManager.repairHashTable: error in options file" +
                ", '$([PoShLogProfile]::LOOKUP_UNKNOWN)' entry for: '$name'"
              )
            );
          }
        }
      }
      else {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.repairHashTable: error in options file" +
            ", entry for: '$name' is not an object (type: '$($node.$name.GetType())')"
          )
        ); 
      }
    }
    else {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.repairHashTable: error in options file" +
          ", missing hashtable entry for: '$name'"
        )
      );
    }
  }

  [void] verify([PSCustomObject]$options) {
    [array]$checklist = @(
      # Output
      #
      @{ Node = $options.Output; Member = 'GroupBy'; Type = [string]; Path = './Output'; },

      # Output.Selection
      #
      @{ Node = $options.Selection; Member = 'Subject'; Type = [PSCustomObject]; Path = './Selection'; },
      @{ Node = $options.Selection; Member = 'Tags'; Type = [PSCustomObject]; Path = './Tags'; },

      # Output.SourceControl
      #
      @{ Node = $options.SourceControl; Member = 'AvatarSize'; Type = [string]; Path = './SourceControl'; },
      @{ Node = $options.SourceControl; Member = 'CommitIdSize'; Type = [long]; Path = './SourceControl'; },

      # Output.Headings
      #
      @{ Node = $options.Output.Headings; Member = 'Dirty'; Type = [string]; Path = './Output/Headings'; }

      # Output.Sections
      #
      @{ Node = $options.Output.Sections; Member = 'Release'; Type = [PSCustomObject]; Path = './Output/Sections'; }

      # Output.Sections.Release
      #
      @{ Node = $options.Output.Sections.Release; Member = 'Highlights'; Type = [string]; Path = './Output/Sections/Release'; }
      @{ Node = $options.Output.Sections.Release; Member = 'HighlightContent'; Type = [array]; Path = './Output/Sections/Release'; }

      # Output.Literals
      #
      @{ Node = $options.Output.Literals; Member = 'Broken'; Type = [string]; Path = './Output.Literals'; },
      @{ Node = $options.Output.Literals; Member = 'BucketEnd'; Type = [string]; Path = './Output.Literals'; },
      @{ Node = $options.Output.Literals; Member = 'DateFormat'; Type = [string]; Path = './Output.Literals'; },
      @{ Node = $options.Output.Literals; Member = 'Dirty'; Type = [string]; Path = './Output.Literals'; },
      @{ Node = $options.Output.Literals; Member = 'Uncategorised'; Type = [string]; Path = './Output.Literals'; },

      # Output.Statements
      #
      @{ Node = $options.Output.Statements; Member = 'Break'; Type = [string]; Path = './Output.Statements'; },
      @{ Node = $options.Output.Statements; Member = 'Change'; Type = [string]; Path = './Output.Statements'; },
      @{ Node = $options.Output.Statements; Member = 'Scope'; Type = [string]; Path = './Output.Statements'; },
      @{ Node = $options.Output.Statements; Member = 'Type'; Type = [string]; Path = './Output.Statements'; },
      @{ Node = $options.Output.Statements; Member = 'Commit'; Type = [string]; Path = './Output.Statements'; },
      @{ Node = $options.Output.Statements; Member = 'DirtyCommit'; Type = [string]; Path = './Output.Statements'; }
    );

    $checklist | ForEach-Object {
      $this.verifyIsPresent($_.Node, $_.Member, $_.Type, $_.Path);
    }    
  }

  [void] verifyIsPresent ([PSCustomObject]$node, [string]$member, [Type]$type, [string]$path) {
    if ($null -ne $node.$member) {
      if (-not($node.$member -is $type)) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          $(
            "PoShLogOptionsManager.verifyIsPresent: error in options file" +
            ", '$member' at '$path' is of wrong type, expected: " +
            "'$($type)', found: '$($node.$member.GetType())'"
          )
        );
      }
    }
    else {
      throw [System.Management.Automation.MethodInvocationException]::new(
        $(
          "PoShLogOptionsManager.verifyIsPresent: error in options file" +
          ", missing '$member' at '$path'"
        )
      );
    }
  }

  static [string] $DEFAULT_TEMPLATE = `
    @"
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
[[warnings]]
[[content]]
[[links]]
[[schema-version]]
Powered By [:scroll: Elizium.PoShLog](https://github.com/EliziumNet/PoShLog)
"@
} # PoShLogOptionsManager

# === [ LineAppender ] =========================================================
# Prevents 2 consecutive blank lines from being created in the string builder
# and relieves the user from having to work out correct statement definitions
# that avoids consecutive blanks lines which then go on to cause a markdown
# warning.
#
class LineAppender {
  hidden [System.Text.StringBuilder]$_builder;
  hidden [string]$_previous = 'I Wish I Had Duck Feet';

  LineAppender() {
    $this._builder = [System.Text.StringBuilder]::new();
  }

  [void] AppendLine([string]$value) {
    if (-not([string]::IsNullOrEmpty($this._previous) -and ([string]::IsNullOrEmpty($value)))) {
      $this._builder.AppendLine($value);
    }

    $this._previous = $value;
  }

  [string] ToString() {
    return $this._builder.ToString();
  }
}
