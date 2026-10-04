#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:RIGMMAKER_SETTINGS_DIR=Join-Path $projectRoot 'Win64\Validation\IsolatedSettings\Run-DpiValidation'
$validationRoot = Join-Path $projectRoot 'Win64\Validation'
$paths = @('Source\Studio','Source\Lib\Voicevox','Source\Core','Source\Editor','Source\Rendering','Source\Persistence','Source\Integrations','Source\Shell','Source\Lib\GameControllers','Source\Lib\UI\IconToolbar','Source\Reference\AIArtToPSD\Core','Source\Reference\AIArtToPSD\Persistence\PNG','Source\Reference\AIArtToPSD\Persistence\PSD','Source\Reference\AIArtToPSD\Integrations\Pipe','Source\Reference\AIArtToPSD\Shell','Source\Reference\AIArtToPSD\Lib\UI\VerticalScrollBar','Source\Reference\AIArtToPSD\Lib\UI\HorizontalTrackBar','Source\Reference\AIArtToPSD\Lib\Pipe') -join ';'
$dcu = Join-Path $validationRoot 'RigmDpiTestsDcu'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
Push-Location $projectRoot
try {
    $command = 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && dcc64 -B -Q -U"'+$paths+'" -E"'+$validationRoot+'" -N0"'+$dcu+'" Tests\RigmDpiTests.dpr'
    $output = & cmd.exe /d /s /c $command 2>&1
    $output | Set-Content (Join-Path $validationRoot 'build-RigmDpiTests.log') -Encoding utf8
    if($LASTEXITCODE -ne 0) { throw 'DPI test compilation failed' }
    $output = & (Join-Path $validationRoot 'RigmDpiTests.exe') ('--data-dir='+ (Join-Path $validationRoot 'DpiLibrary')) ('--pipe-dir='+ (Join-Path $validationRoot 'DpiPipes')) 2>&1
    $code=$LASTEXITCODE
    $output | Set-Content (Join-Path $validationRoot 'RigmDpiTests.log') -Encoding utf8
    $output | Write-Output
    if($code -ne 0) { throw 'DPI regression failed' }
} finally { Pop-Location }
