#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $root 'Win64\Validation\IsolatedSettings\Run-MovieValidation'
$output=Join-Path $root 'Win64\Validation'
$dcu=Join-Path $output 'RigmMovieTestsDcu'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$paths=@('Source\Studio','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD') -join ';'
Push-Location $root
try {
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$output+'" -N0"'+$dcu+'" Tests\RigmMovieTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1
  $code=$LASTEXITCODE
  $build | Set-Content (Join-Path $output 'build-RigmMovieTests.log') -Encoding utf8
  $build
  if($code -ne 0){throw "Movie test build failed: $code"}
  $test=& (Join-Path $output 'RigmMovieTests.exe') 2>&1
  $code=$LASTEXITCODE
  $test | Set-Content (Join-Path $output 'RigmMovieTests.log') -Encoding utf8
  $test
  if($code -ne 0){throw "Movie tests failed: $code"}
} finally {Pop-Location}
