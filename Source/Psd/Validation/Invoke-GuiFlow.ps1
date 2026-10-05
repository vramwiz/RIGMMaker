param([ValidateSet('Debug','Release')][string]$Configuration='Debug', [string]$DataRoot='D:\Users\take6\RIGMMaker')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$validation=Join-Path $repo 'Win64\Validation\PsdStudio'
$root=Join-Path $validation ('GuiCheck\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $DataRoot 'Characters\blonde-android-20261005.psdchar') -Destination (Join-Path $root 'Characters\fixture.psdchar')
'{"owner":"RIGMMaker.GuiValidation.v1"}' | Set-Content -LiteralPath (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$result=Join-Path $validation ('gui-flow-'+$Configuration.ToLower()+'.json')
$snapshot=Join-Path $validation ('gui-flow-'+$Configuration.ToLower()+'.png')
$exe=Join-Path $validation ($Configuration+'\PsdStudio.exe')
$arguments=@('--root',('"'+$root+'"'),'--verify-gui',('"'+$result+'"'),'--smoke',('"'+$snapshot+'"'))
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(18000) -or $process.ExitCode -ne 0) { throw 'GUI regression failed or still active; do not terminate' }
$checks=@(Get-Content -Encoding UTF8 -LiteralPath $result -Raw | ConvertFrom-Json)
if($checks.Count -ne 9) { throw 'Missing GUI flow checks' }
[pscustomobject]@{configuration=$Configuration;root=$root;result=$result;snapshot=$snapshot;processId=$process.Id;normalExit=$true;checks=$checks.Count;method='native-controls-and-existing-events; no physical mouse or file-dialog automation'} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $validation ('gui-flow-'+$Configuration.ToLower()+'-metadata.json'))
