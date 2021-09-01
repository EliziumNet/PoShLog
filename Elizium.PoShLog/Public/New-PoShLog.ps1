
function New-PoShLog {
  <#
  .NAME
    New-PoShLog

  .SYNOPSIS
    Create PoShLog instance

  .DESCRIPTION
    Factory function for PoShLog instances.

  .LINK
    https://eliziumnet.github.io/klassy

  .PARAMETER Options
    PoShLog options
  #>
  [OutputType([PoShLog])]
  param(
    [PSCustomObject]$Options
  )
  [ProxyGit]$proxy = [ProxyGit]::New();
  [SourceControl]$git = [Git]::new($Options, $proxy);
  [GroupByImpl]$grouper = [GroupByImpl]::new($Options);
  [MarkdownPoShLogGenerator]$generator = [MarkdownPoShLogGenerator]::new(
    $Options, $git, $grouper
  );
  [PoShLog]$instance = [PoShLog]::new($Options, $git, $grouper, $generator);

  $instance.Init();
  return $instance;
}
