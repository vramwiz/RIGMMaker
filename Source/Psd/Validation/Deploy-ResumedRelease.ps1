param([string]$ExpectedPreviousHash='0C8688539EE3D5E3B89151C620403A4F529CCC28470E75D85AE51CBF355927C5')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$target=Join-Path $repo 'RIGMMaker.exe'
$source=Join-Path $repo 'Win64\Validation\IntegratedPsd\Release\RIGMMaker.exe'
$out=Join-Path $repo 'Win64\Validation\PsdStudio'
$recovery=Join-Path $out ('Recovery\resumed-20261005\'+[guid]::NewGuid().ToString('N'))
foreach($taskPath in @($target,$source,$recovery)){
 if(-not [IO.Path]::GetFullPath($taskPath).StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment path outside workspace'}
}
if(@(Get-Process -Name RIGMMaker,RIGMWizard -ErrorAction SilentlyContinue).Count -ne 0){throw 'Application is active; deployment withheld'}
$before=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if($before -ne $ExpectedPreviousHash){throw 'User executable changed; deployment withheld'}
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
New-Item -ItemType Directory -Path $recovery -Force|Out-Null
$stage=Join-Path $recovery 'RIGMMaker-release-staged.exe'
$backup=Join-Path $recovery 'RIGMMaker-before.exe'
Copy-Item -LiteralPath $source -Destination $stage
if((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $sourceHash){throw 'Staging hash mismatch'}
if(@(Get-Process -Name RIGMMaker,RIGMWizard -ErrorAction SilentlyContinue).Count -ne 0){throw 'Application started; deployment withheld'}
if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $before){throw 'Executable changed during staging; deployment withheld'}
[IO.File]::Replace($stage,$target,$backup,$true)
if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $before){throw 'Backup hash mismatch'}
$after=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if($after -ne $sourceHash){throw 'Deployed executable hash mismatch'}
@{deployed=$true;source=$source;target=$target;beforeHash=$before;afterHash=$after;backup=$backup;noUserAppsKilled=$true;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Tee-Object -FilePath (Join-Path $out 'deployment-resumed.json')
