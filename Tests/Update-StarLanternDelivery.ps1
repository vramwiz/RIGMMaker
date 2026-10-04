#requires -Version 7.0
param(
  [string]$ImageDirectory = 'D:\DelphiProg\RIGMMaker\制作素材\星灯り郵便局',
  [string]$Destination = 'D:\DelphiProg\RIGMMaker\制作成果\星灯り郵便局-編集版-20261004T015824236'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root '制作成果\星灯り郵便局-20261003T224130881\星灯り郵便局.rigmovie'
$output = Join-Path $root 'Win64\Validation\StarLanternDelivery'
$dcu = Join-Path $output 'Dcu'
New-Item -ItemType Directory -Path $output,$dcu -Force | Out-Null
$paths = @('Source\Studio','Source\Studio\Assets','Source\Studio\Audio','Source\Studio\Model','Source\Studio\Output','Source\Studio\Rendering','Source\Studio\Session','Source\Studio\Views\Creation','Source\Studio\Views\Editor','Source\Studio\Views\Preview','Source\Studio\Views\Timeline','Source\Studio\Workflow','Source\Shell\CharacterEditor','Source\Core','Source\Rendering','Source\Persistence','Source\Editor','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD') -join ';'
Push-Location $root
try {
  $cmd = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$output+'" -N0"'+$dcu+'" Tests\RigmStarLanternDelivery.dpr'
  & cmd.exe /d /s /c $cmd 2>&1 | Set-Content -LiteralPath (Join-Path $output 'build.log') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Edited work builder failed to compile' }
  & (Join-Path $output 'RigmStarLanternDelivery.exe') "--source=$source" "--destination=$Destination" "--images=$ImageDirectory"
  if ($LASTEXITCODE -ne 0) { throw 'Edited work integration failed' }
  Get-Content -LiteralPath (Join-Path $Destination 'edited-verification.json') -Raw -Encoding UTF8 | ConvertFrom-Json | Select-Object success,complete,acceptedImages,sourceUnchanged,reopened,durationSeconds,path
} finally { Pop-Location }
