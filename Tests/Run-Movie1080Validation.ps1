#requires -Version 7.0
param([int]$Cues=2,[ValidateSet('fast','balanced','quality')][string]$Profile='fast',[string]$FFmpegDirectory='C:\Users\zan12\Downloads\ffmpeg-8.1.1-full_build-shared\ffmpeg-8.1.1-full_build-shared\bin')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$m=Get-Content (Join-Path $root 'Win64\Validation\quality-material.json') -Raw | ConvertFrom-Json
$out=Join-Path $root 'Win64\Validation';$dcu=Join-Path $out 'Movie1080Dcu';New-Item -ItemType Directory -Path $dcu -Force|Out-Null
$paths=@('Source\Studio','Source\Studio\Assets','Source\Studio\Audio','Source\Studio\Model','Source\Studio\Output','Source\Studio\Rendering','Source\Studio\Session','Source\Studio\Views\Creation','Source\Studio\Views\Editor','Source\Studio\Views\Preview','Source\Studio\Views\Timeline','Source\Studio\Workflow','Source\Shell\CharacterEditor','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD') -join ';'
Push-Location $root
try{
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -GD -U"'+$paths+'" -E"'+$out+'" -N0"'+$dcu+'" Tests\RigmMovie1080Tests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1;$code=$LASTEXITCODE;$build|Set-Content (Join-Path $out 'build-Movie1080Tests.log') -Encoding utf8;$build
  if($code -ne 0){throw '1080 build failed'}
  & (Join-Path $out 'RigmMovie1080Tests.exe') (Join-Path $m.directory 'Kiritan-prepared-copy.rigm') (Join-Path $FFmpegDirectory 'ffmpeg.exe') $Profile $Cues | Tee-Object -FilePath (Join-Path $out ('Movie1080-'+$Cues+'-'+$Profile+'.log'))
  if($LASTEXITCODE -ne 0){throw '1080 tests failed'}
}finally{Pop-Location}
