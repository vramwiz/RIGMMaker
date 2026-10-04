#requires -Version 7.0
param([string]$Mode='before')
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$m=Get-Content (Join-Path $root 'Win64\Validation\quality-material.json') -Raw | ConvertFrom-Json
$out=Join-Path $root 'Win64\Validation';$dcu=Join-Path $out 'QualityDcu';New-Item -ItemType Directory -Path $dcu -Force|Out-Null
$paths=@('Source\Studio','Source\Lib\Charts','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD') -join ';'
Push-Location $root
try{
  $cmd='call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$out+'" -N0"'+$dcu+'" Tests\RigmMovieQualityTests.dpr'
  $build=& cmd.exe /d /s /c $cmd 2>&1;$code=$LASTEXITCODE;$build|Set-Content (Join-Path $out 'build-MovieQualityTests.log') -Encoding utf8;$build
  if($code -ne 0){throw 'Quality build failed'}
  & (Join-Path $out 'RigmMovieQualityTests.exe') $m.copy $m.directory $Mode | Tee-Object -FilePath (Join-Path $out ('MovieQuality-'+$Mode+'.log'))
  if($LASTEXITCODE -ne 0){throw 'Quality tests failed'}
}finally{Pop-Location}
