param([ValidateSet('Debug','Release')][string]$Configuration='Debug',[string]$DataRoot='D:\Users\take6\RIGMMaker',[ValidateSet('RIGMWizard','RIGMMaker')][string]$ExecutableName='RIGMWizard',[string]$ExecutablePath='')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$validation=Join-Path $repo 'Win64\Validation\PsdStudio'
$root=Join-Path 'C:\Users\vramw\AppData\Local\Temp' ('RIGMMaker-WizardCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $DataRoot 'Characters\blonde-android-20261005.psdchar') -Destination (Join-Path $root 'Characters\fixture.psdchar')
& (Join-Path $PSScriptRoot 'Reset-ValidationFixture.ps1') -Fixture (Join-Path $root 'Characters\fixture.psdchar')
'{"owner":"RIGMMaker.GuiValidation.v1"}' | Set-Content -LiteralPath (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$result=Join-Path $validation ('wizard-flow-'+$Configuration.ToLower()+'.json')
$snapshot=Join-Path $validation ('wizard-flow-'+$Configuration.ToLower()+'.png')
$exe=Join-Path $repo ('Win64\Validation\IntegratedPsd\'+$Configuration+'\'+$ExecutableName+'.exe')
if($ExecutablePath -ne ''){$exe=[IO.Path]::GetFullPath($ExecutablePath)}
$arguments=@('--data-root',('"'+$root+'"'),'--verify-wizard',('"'+$result+'"'),'--smoke',('"'+$snapshot+'"'))
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
if(-not $process.WaitForExit(55000)){throw 'Wizard validation still active; do not terminate or move its work root'}
if($process.ExitCode -ne 0){if(Test-Path -LiteralPath ($result+'.error.txt')){Get-Content -Encoding UTF8 -LiteralPath ($result+'.error.txt')}; throw 'Wizard validation failed'}
$checks=@(Get-Content -Encoding UTF8 -LiteralPath $result -Raw | ConvertFrom-Json)
$pageChecks=@(Get-Content -Encoding UTF8 -LiteralPath ($result+'.pages.json') -Raw | ConvertFrom-Json)
if($checks.Count -ne 28 -or $pageChecks.Count -ne 11){throw 'Missing wizard or page checks'}
[pscustomobject]@{configuration=$Configuration;executable=$exe;root=$root;result=$result;snapshot=$snapshot;normalExit=$true;checks=$checks.Count;pageChecks=$pageChecks.Count;method='native-controls-and-events; no physical mouse/file-dialog automation'} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $validation ('wizard-flow-'+$Configuration.ToLower()+'-metadata.json'))
