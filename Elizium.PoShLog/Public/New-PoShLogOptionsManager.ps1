
function New-PoShLogOptionsManager {
  param(
    [Parameter()]
    [PSCustomObject]$OptionsInfo,

    [Parameter()]
    [ProxyGit]$Proxy
  )

  [PoShLogOptionsManager]$manager = [PoShLogOptionsManager]::new(
    $Proxy ?? [ProxyGit]::new(),
    $OptionsInfo
  );
  $manager.Init();

  return $manager;
}
