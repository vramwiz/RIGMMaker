param([Parameter(Mandatory=$true)][string]$OutDir,[string]$ProjectFile,[int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output=[IO.Path]::GetFullPath($OutDir)
if(Test-Path -LiteralPath $output){throw 'Fresh output required'}
$bin=Join-Path $output 'bin'; $dcu=Join-Path $output 'dcu'; $run=Join-Path $output 'run'
New-Item -ItemType Directory -Path $bin,$dcu,$run | Out-Null
$source=Join-Path $output 'MovieRenderMp4Check.dpr'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MovieRenderMp4Check.dpr') -Destination $source
[xml]$project=Get-Content -LiteralPath (Join-Path $repo 'RIGMMaker.dproj') -Raw
$ns=[Xml.XmlNamespaceManager]::new($project.NameTable)
$ns.AddNamespace('m','http://schemas.microsoft.com/developer/msbuild/2003')
$paths=@($project.SelectSingleNode('//m:DCC_UnitSearchPath',$ns).InnerText -split ';' | Where-Object {$_ -and -not $_.StartsWith('$(')} | ForEach-Object {Join-Path $repo $_})
$flags=@('-B','-Q',('-E'+$bin),('-N0'+$dcu),('-U'+($paths -join ';')),'-NSSystem;Winapi;Vcl;System.Win;Xml;Data','-$O+','-$R-','-$Q-')
Push-Location $output
try {
  & 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' @flags $source *> (Join-Path $output 'build.log')
  if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 12; throw 'MP4 render-check build failed'}
  Copy-Item -LiteralPath (Join-Path $repo 'Runtime') -Destination (Join-Path $bin 'Runtime') -Recurse
  $probeArguments='"'+$run+'"'
  if($ProjectFile){$probeArguments+=' "'+([IO.Path]::GetFullPath($ProjectFile))+'"'}
  $p=Start-Process -FilePath (Join-Path $bin 'MovieRenderMp4Check.exe') -ArgumentList $probeArguments -WorkingDirectory $output -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'result.txt') -RedirectStandardError (Join-Path $output 'stderr.txt')
  $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while(-not $p.WaitForExit(1000)) {
    if([DateTime]::UtcNow -gt $deadline){throw ('Owned MP4 probe timed out; PID='+$p.Id+'; output='+$output)}
  }
  Get-Content -LiteralPath (Join-Path $output 'result.txt') -Tail 10
  if($p.ExitCode -ne 0){throw ('MP4 render check failed: '+$p.ExitCode)}
} finally {Pop-Location}
