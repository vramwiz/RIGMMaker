#requires -Version 7.0
param([Parameter(Mandatory)][string]$SourceMovie)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.Path]::GetFullPath($SourceMovie)
if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw 'Provide the actual four-scene image/voice source movie'}
$validation=Join-Path $root 'Win64\Validation'
$fixture=Join-Path $validation ('TimelineExportFixture\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$dcu=Join-Path $validation 'RigmTimelineExportTestsDcu'
New-Item -ItemType Directory -Path $fixture,$dcu,(Join-Path $fixture 'Pipes'),(Join-Path $fixture 'Library') -Force|Out-Null
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $fixture 'settings'
$before=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$paths=@('Tests','Source\Studio','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
Push-Location $root
try {
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$validation+'" -N0"'+$dcu+'" Tests\RigmTimelineExportTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1
  $code=$LASTEXITCODE
  $build|Set-Content -LiteralPath (Join-Path $fixture 'build.log') -Encoding utf8
  if($code -ne 0){throw "Native timeline/export build failed: $code"}
  $test=Start-Process -FilePath (Join-Path $validation 'RigmTimelineExportTests.exe') -ArgumentList @(('"'+$source+'"'),('"'+$fixture+'"'),('"--pipe-dir='+(Join-Path $fixture 'Pipes')+'"'),('"--data-dir='+(Join-Path $fixture 'Library')+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $fixture 'stdout.log') -RedirectStandardError (Join-Path $fixture 'stderr.log')
  @{pid=$test.Id;fixture=$fixture;source=$source;sourceSha256=$before;native=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'run.json') -Encoding utf8
  $test.WaitForExit()
  if($test.ExitCode -ne 0){Get-Content -LiteralPath (Join-Path $fixture 'stdout.log');throw "Native GUI checks failed: $($test.ExitCode)"}
  if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $before){throw 'Source work changed during owned GUI verification'}
  Get-Content -LiteralPath (Join-Path $fixture 'results.json') -Raw
} finally {Pop-Location}
