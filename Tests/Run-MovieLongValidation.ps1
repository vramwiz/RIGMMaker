#requires -Version 7.0
param([string]$FFmpegDirectory='C:\Users\zan12\Downloads\ffmpeg-8.1.1-full_build-shared\ffmpeg-8.1.1-full_build-shared\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $root 'Win64\Validation\IsolatedSettings\Run-MovieLongValidation'
$output=Join-Path $root 'Win64\Validation'
$dcu=Join-Path $output 'RigmMovieLongTestsDcu'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$paths=@('Source\Studio','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD') -join ';'
Push-Location $root
try{
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$output+'" -N0"'+$dcu+'" Tests\RigmMovieLongTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1;$code=$LASTEXITCODE
  $build | Set-Content (Join-Path $output 'build-MovieLongTests.log') -Encoding utf8
  $build;if($code -ne 0){throw "Long test build failed: $code"}
  & (Join-Path $output 'RigmMovieLongTests.exe') (Join-Path $FFmpegDirectory 'ffmpeg.exe') | Tee-Object -FilePath (Join-Path $output 'MovieLongTests.log')
  if($LASTEXITCODE -ne 0){throw 'Long tests failed'}
  & (Join-Path $PSScriptRoot 'Inspect-MovieLong.ps1') -FFmpegDirectory $FFmpegDirectory
}finally{Pop-Location}
