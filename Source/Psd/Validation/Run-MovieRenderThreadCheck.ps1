param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
# This check renders generated pixels and captions only. Never calls audio load, mix, encode or playback.
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $output){throw 'Fresh output required'}
$bin=Join-Path $output 'bin';$dcu=Join-Path $output 'dcu';$run=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$run | Out-Null
$source=Join-Path $output 'MovieRenderThreadCheck.dpr'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MovieRenderThreadCheck.dpr') -Destination $source
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable);$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-$O+','-$R-','-$Q-')
Push-Location $output
try {
  & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags $source *> (Join-Path $output 'build.log')
  if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 12;throw 'Thread-check build failed'}
  $p=Start-Process -FilePath (Join-Path $bin 'MovieRenderThreadCheck.exe') -ArgumentList ('"'+$run+'"') -WorkingDirectory $output -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'result.txt') -RedirectStandardError (Join-Path $output 'stderr.txt')
  $deadline=[DateTime]::UtcNow.AddSeconds(240)
  while(-not $p.WaitForExit(1000)) {
    if([DateTime]::UtcNow -gt $deadline){throw ('Owned silent probe timed out; PID='+$p.Id+'; output='+$output)}
  }
  Get-Content -LiteralPath (Join-Path $output 'result.txt') -Tail 8
  if($p.ExitCode -ne 0){throw ('Silent thread check failed: '+$p.ExitCode)}
} finally {Pop-Location}