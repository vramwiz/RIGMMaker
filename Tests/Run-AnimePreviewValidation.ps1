#requires -Version 7.0
param([string]$ProductionDirectory,[string]$CharacterFile='C:\Users\zan12\Documents\RIGMMaker\RIGM\character-904B63CF-20D7-4FB4-B8C0-11CB570949B5.rigm')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $root 'Win64\Validation\IsolatedSettings\Run-AnimePreviewValidation'
$validation=Join-Path $root 'Win64\Validation'
$id=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
if(-not $ProductionDirectory){$ProductionDirectory=Join-Path $root ('制作成果\星灯り郵便局-'+$id)}
if(Test-Path -LiteralPath (Join-Path $ProductionDirectory '星灯り郵便局.rigmovie')){throw 'An existing user production must not be overwritten'}
$pipes=Join-Path $validation ('AnimePreviewPipes\'+$id)
$dcu=Join-Path $validation 'RigmAnimePreviewTestsDcu'
$paths=@('Tests','Source\Studio','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
New-Item -ItemType Directory -Path $ProductionDirectory,$pipes,$dcu -Force | Out-Null
$version=Invoke-RestMethod -Uri 'http://127.0.0.1:50021/version' -TimeoutSec 3
$catalog=Invoke-RestMethod -Uri 'http://127.0.0.1:50021/speakers' -TimeoutSec 5
if(-not($catalog|Where-Object {$_.name -eq '東北きりたん' -and ($_.styles.id -contains 108)})){throw 'The actual local engine does not supply Kiritan style 108'}
Push-Location $root
try {
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$validation+'" -N0"'+$dcu+'" Tests\RigmAnimePreviewTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1; $code=$LASTEXITCODE
  $build|Set-Content -LiteralPath (Join-Path $validation 'build-AnimePreviewTests.log') -Encoding UTF8
  $build; if($code -ne 0){throw 'Anime preview compilation failed'}
  $process=Start-Process -FilePath (Join-Path $validation 'RigmAnimePreviewTests.exe') -ArgumentList @(('"--production-dir='+$ProductionDirectory+'"'),('"--character='+$CharacterFile+'"'),('"--pipe-dir='+$pipes+'"'),('"--data-dir='+(Join-Path $pipes 'Library')+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $validation 'AnimePreviewTests.log') -RedirectStandardError (Join-Path $pipes 'stderr.log')
  $process.WaitForExit(); Get-Content -LiteralPath (Join-Path $validation 'AnimePreviewTests.log')
  if($process.ExitCode -ne 0){throw ('Actual speech preview verification failed; retained independent outputs: '+$ProductionDirectory)}
  $result=Get-Content -LiteralPath (Join-Path $ProductionDirectory 'verification.json') -Raw -Encoding UTF8|ConvertFrom-Json
  $result|Add-Member -NotePropertyName engineVersion -NotePropertyValue $version
  $result|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $validation 'anime-preview-results.json') -Encoding UTF8
}finally{Pop-Location}
