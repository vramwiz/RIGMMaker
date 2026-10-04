#requires -Version 7.0
param([string]$SourceProject)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$output=Join-Path $root 'Win64\Validation'
if(-not $SourceProject){$SourceProject=(Get-ChildItem (Join-Path $root '制作成果') -Filter '*.rigmovie' -Recurse -File | Select-Object -First 1).FullName}
$fixture=Join-Path $output ('Resume\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'))
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $fixture 'Settings'
$env:RIGMMAKER_RESUME_TEST_ROOT=$fixture
$env:RIGMMAKER_RESUME_TEST_SOURCE=$SourceProject
$dcu=Join-Path $output 'RigmResumeTestsDcu'
New-Item -ItemType Directory -Path $fixture,$dcu -Force | Out-Null
$paths=@('Tests','Source\Studio','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
Push-Location $root
try {
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$output+'" -N0"'+$dcu+'" Tests\RigmResumeTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1; $code=$LASTEXITCODE
  $build | Set-Content (Join-Path $output 'build-ResumeTests.log') -Encoding utf8
  $build
  if($code -ne 0){throw 'Resume validation build failed'}
  & (Join-Path $output 'RigmResumeTests.exe') ('--pipe-dir='+ (Join-Path $fixture 'Pipes')) ('--data-dir='+ (Join-Path $fixture 'Library')) *> (Join-Path $output 'ResumeTests.log')
  $code=$LASTEXITCODE; Get-Content (Join-Path $output 'ResumeTests.log')
  if($code -ne 0){throw 'Resume validation failed'}
}finally{Pop-Location}
