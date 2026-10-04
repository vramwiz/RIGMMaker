#requires -Version 7.0
param([string]$FFmpegDirectory='C:\Users\zan12\Downloads\ffmpeg-8.1.1-full_build-shared\ffmpeg-8.1.1-full_build-shared\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $root 'Win64\Validation\IsolatedSettings\Run-MovieWorkflowValidation'
$output=Join-Path $root 'Win64\Validation'
$id=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
$fixture=Join-Path $output ('MovieFixture\'+$id)
$dcu=Join-Path $output 'RigmMovieWorkflowTestsDcu'
$pipes=Join-Path $output ('MovieWorkflowPipes\'+$id)
$paths=@('Tests','Source\Studio','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
New-Item -ItemType Directory -Path $fixture,$dcu,$pipes -Force | Out-Null
$process=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-File',('"'+(Join-Path $PSScriptRoot 'VoicevoxFixture.ps1')+'"'),'-Directory',('"'+$fixture+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $fixture 'stdout.log') -RedirectStandardError (Join-Path $fixture 'stderr.log')
try {
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while(-not (Test-Path (Join-Path $fixture 'fixture-ready.txt')) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
  if(-not (Test-Path (Join-Path $fixture 'fixture-ready.txt'))){throw 'Local fixture could not start'}
  Push-Location $root
  try {
    $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$output+'" -N0"'+$dcu+'" Tests\RigmMovieWorkflowTests.dpr'
    $build=& cmd.exe /d /s /c $cmd 2>&1;$code=$LASTEXITCODE
    $build | Set-Content (Join-Path $output 'build-MovieWorkflowTests.log') -Encoding utf8
    $build
    if($code -ne 0){throw "Workflow build failed: $code"}
    $exe=Join-Path $output 'RigmMovieWorkflowTests.exe'
    $test=Start-Process -FilePath $exe -ArgumentList @(('"--pipe-dir='+$pipes+'"'),('"--data-dir='+(Join-Path $fixture 'Library')+'"'),('"--fixture-dir='+$fixture+'"'),('"--ffmpeg='+(Join-Path $FFmpegDirectory 'ffmpeg.exe')+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $output 'MovieWorkflowTests.log') -RedirectStandardError (Join-Path $fixture 'workflow-stderr.log')
    $test.WaitForExit(); if($test.ExitCode -ne 0){Get-Content (Join-Path $output 'MovieWorkflowTests.log');throw "Workflow tests failed: $($test.ExitCode)"}
    Get-Content (Join-Path $output 'MovieWorkflowTests.log')
    $result=Get-Content (Join-Path $output 'movie-workflow-results.json') -Raw | ConvertFrom-Json
    & (Join-Path $PSScriptRoot 'Inspect-MovieAvi.ps1') -Avi (Join-Path $result.directory 'workflow-tone.avi') -FFmpegDirectory $FFmpegDirectory -OutputDirectory (Join-Path $result.directory 'DecodedAVI')
    & (Join-Path $PSScriptRoot 'Inspect-MovieAvi.ps1') -Avi (Join-Path $result.directory 'workflow-tone.mp4') -FFmpegDirectory $FFmpegDirectory -OutputDirectory (Join-Path $result.directory 'DecodedMP4') -Mp4
  }finally{Pop-Location}
}finally{
  Set-Content (Join-Path $fixture 'fixture-stop.txt') 'stop'
  $process.WaitForExit(5000) | Out-Null
}
