#requires -Version 7.0
param([Parameter(Mandatory)][string]$TaskDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$TaskDirectory=[IO.Path]::GetFullPath($TaskDirectory)
if(-not $TaskDirectory.StartsWith((Join-Path $root 'Win64\Validation\ImageTransfer-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected image-transfer task directory'}
foreach($config in @('Debug','Release')){
  $result=[IO.File]::ReadAllText((Join-Path $TaskDirectory ('Actual-'+$config+'-Final\run.json')))|ConvertFrom-Json -AsHashtable
  if(-not $result.success -or -not $result.closedNormally -or $result.checkCount -lt 51){throw ('Incomplete final transfer validation: '+$config)}
  $binary=Join-Path $TaskDirectory ('Build\'+$config+'\RIGMMaker.exe')
  if((Get-FileHash -LiteralPath $binary).Hash -ne $result.executableSha256){throw ('Validated binary changed: '+$config)}
}
$release=Join-Path $TaskDirectory 'Build\Release\RIGMMaker.exe'
$releaseHash=(Get-FileHash -LiteralPath $release).Hash
$normal=Join-Path $root 'RIGMMaker.exe'
$originalHash=(Get-FileHash -LiteralPath $normal).Hash
$preserved=Join-Path $TaskDirectory 'Preserved';New-Item -ItemType Directory -Path $preserved -Force | Out-Null
$backup=Join-Path $preserved ('root-before-image-transfer-'+$originalHash.Substring(0,12)+'.exe')
if(-not (Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $normal -Destination $backup -ErrorAction Stop}
if((Get-FileHash -LiteralPath $backup).Hash -ne $originalHash){throw 'Original root EXE backup differs'}
$stage=Join-Path $root ('RIGMMaker.image-transfer-stage-'+[guid]::NewGuid().ToString('N')+'.exe')
Copy-Item -LiteralPath $release -Destination $stage -ErrorAction Stop
if((Get-FileHash -LiteralPath $stage).Hash -ne $releaseHash){throw 'Deployment stage differs from validated Release'}
if((Get-FileHash -LiteralPath $normal).Hash -ne $originalHash){throw 'Root EXE changed during backup; deployment halted'}
$report=@{originalRootSha256=$originalHash;preserved=$backup;preservedSha256=(Get-FileHash -LiteralPath $backup).Hash;validatedRelease=$release;validatedReleaseSha256=$releaseHash;userAppsTerminated=$false;rootReplaced=$false;utc=[DateTime]::UtcNow.ToString('o')}
try{
  [IO.File]::Move($stage,$normal,$true)
  $report.rootReplaced=$true;$report.executable=$normal
}catch{
  $report.rootReplacementError=$_.Exception.Message
  $alias=Join-Path $root ('RIGMMaker.image-transfer-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'.exe')
  [IO.File]::Move($stage,$alias)
  $report.executable=$alias
}
$report.executableSha256=(Get-FileHash -LiteralPath $report.executable).Hash
if($report.executableSha256 -ne $releaseHash){throw 'Deployed binary differs from validated Release'}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $TaskDirectory 'deployment.json') -Encoding utf8BOM
$report|ConvertTo-Json -Depth 6
