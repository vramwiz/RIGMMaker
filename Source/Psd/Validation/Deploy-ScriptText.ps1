param([Parameter(Mandatory=$true)][string]$BuildRoot,[Parameter(Mandatory=$true)][string]$ExpectedPreviousHash)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$task=[IO.Path]::GetFullPath($BuildRoot)
if(-not $task.StartsWith($repo+'\Win64\Validation\ScriptText\Recovery\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected deployment recovery root'}
$target=Join-Path $repo 'RIGMMaker.exe';$source=Join-Path $task 'Release\RIGMMaker.exe'
$qa=Get-Content -LiteralPath (Join-Path $task 'final-isolated-qa\script-text.json.metadata.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceHash=(Get-FileHash -LiteralPath $source).Hash
if(-not $qa.normalExit -or $qa.exeHash -ne $sourceHash -or $qa.guiChecks -lt 30 -or $qa.restartChecks -lt 9 -or $qa.pipeChecks.Count -ne 17){throw 'Successful matching isolated verification required'}
if(@(Get-Process -Name RIGMMaker,RIGMWizard -ErrorAction SilentlyContinue).Count -ne 0){throw 'Application is active; deployment withheld'}
$before=(Get-FileHash -LiteralPath $target).Hash
if($before -ne $ExpectedPreviousHash){throw 'User executable changed; deployment withheld'}
$stage=Join-Path $task 'RIGMMaker-release-staged.exe';$backup=Join-Path $task 'RIGMMaker-before-deploy.exe'
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $backup)){throw 'Existing recovery file must be preserved'}
Copy-Item -LiteralPath $source -Destination $stage
if((Get-FileHash -LiteralPath $stage).Hash -ne $sourceHash){throw 'Staging hash mismatch'}
if(@(Get-Process -Name RIGMMaker,RIGMWizard -ErrorAction SilentlyContinue).Count -ne 0){throw 'Application started; deployment withheld'}
if((Get-FileHash -LiteralPath $target).Hash -ne $before){throw 'Executable changed during staging; deployment withheld'}
[IO.File]::Replace($stage,$target,$backup,$true)
$after=(Get-FileHash -LiteralPath $target).Hash
if((Get-FileHash -LiteralPath $backup).Hash -ne $before -or $after -ne $sourceHash){throw 'Deployment hash mismatch'}
@{deployed=$true;target=$target;source=$source;backup=$backup;beforeHash=$before;afterHash=$after;noUserAppsKilled=$true;utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $task 'deployment.json')
