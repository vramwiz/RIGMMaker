#requires -Version 7.0
param([string]$SourceProject='制作成果\星灯り郵便局-編集版-20261004T015824236\星灯り郵便局-編集版.rigmovie')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $root ('Win64\Validation\UiRevisionFixture\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$dcu=Join-Path $root 'Win64\Validation\RigmUiRevisionTestsDcu'
New-Item -ItemType Directory -Path $fixture,$dcu -Force|Out-Null
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $fixture 'settings'
$env:RIGMMAKER_UIREV_TEST_ROOT=$fixture
$env:RIGMMAKER_UIREV_TEST_SOURCE=Join-Path $root $SourceProject
$sourceHash=(Get-FileHash -LiteralPath $env:RIGMMAKER_UIREV_TEST_SOURCE).Hash
$paths=@('Tests','Source\Studio','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
$command='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+(Join-Path $root 'Win64\Validation')+'" -N0"'+$dcu+'" Tests\RigmUiRevisionTests.dpr'
$build=& cmd.exe /d /s /c $command 2>&1;$code=$LASTEXITCODE
$build|Set-Content -LiteralPath (Join-Path $root 'Win64\Validation\build-UiRevisionTests.log') -Encoding utf8
if($code -ne 0){$build;throw 'UI regression compilation failed'}
$exe=Join-Path $root 'Win64\Validation\RigmUiRevisionTests.exe'
$test=Start-Process -FilePath $exe -ArgumentList @('"--data-dir='+(Join-Path $fixture 'library')+'"','"--pipe-dir='+(Join-Path $fixture 'pipes')+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $fixture 'stdout.log') -RedirectStandardError (Join-Path $fixture 'stderr.log')
$null=$test.WaitForExit(120000)
if(-not $test.HasExited){throw ('Owned test has not completed; PID '+$test.Id+' was not force-stopped')}
$resultPath=Join-Path $fixture 'results.json'
if($test.ExitCode -ne 0){Get-Content -LiteralPath (Join-Path $fixture 'stdout.log');throw ('UI regression failed '+$test.ExitCode)}
if((Get-FileHash -LiteralPath $env:RIGMMAKER_UIREV_TEST_SOURCE).Hash -ne $sourceHash){throw 'Source production changed'}
Copy-Item -LiteralPath $resultPath -Destination (Join-Path $root 'Win64\Validation\ui-revision-results.json')
Get-Content -LiteralPath $resultPath -Raw
