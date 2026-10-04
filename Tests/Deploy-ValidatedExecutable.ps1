#requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$Executable,
  [Parameter(Mandatory)][string]$GuiResults,
  [Parameter(Mandatory)][string]$ReportPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if($root -ne 'D:\DelphiProg\RIGMMaker'){throw 'Unexpected deployment workspace'}
$exe=[IO.Path]::GetFullPath($Executable)
if(-not $exe.StartsWith((Join-Path $root 'Win64\Validation\CritiqueProduction\BuildFinal')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Only this task final build may be deployed'}
$gui=[IO.File]::ReadAllText($GuiResults) | ConvertFrom-Json -AsHashtable
if(-not $gui.success -or $gui.passed -ne 23 -or $gui.windowsNotificationRequests -ne 1){throw 'Current native GUI verification is required'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$target=Join-Path $root 'RIGMMaker.exe'
$oldHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$preserved=Join-Path $root 'Win64\Validation\CritiqueProduction\Preserved'
$backup=Join-Path $preserved 'root-at-start.exe'
if(-not (Test-Path -LiteralPath $backup) -or (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $oldHash){
  $backup=Join-Path $preserved ('root-before-final-deployment-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.exe')
  if(Test-Path -LiteralPath $backup){throw 'Backup destination already exists'}
  Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
}
if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $oldHash){throw 'Original executable backup is not byte-identical'}
$stage=Join-Path $root ('RIGMMaker.exe.delivery.'+[guid]::NewGuid().ToString('N'))
[IO.File]::Copy($exe,$stage,$false)
if((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $hash){throw 'Staged executable differs from the verified build'}
if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $oldHash){throw 'Root executable changed during preparation; preserve the staged build for review'}
$alias=$false;$reason=''
try{
  # Same-directory rename publishes the fully copied executable in one operation.
  [IO.File]::Move($stage,$target,$true)
}catch [IO.IOException]{
  $alias=$true;$reason=$_.Exception.Message
}catch [UnauthorizedAccessException]{
  $alias=$true;$reason=$_.Exception.Message
}
if($alias){
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $oldHash){throw 'Root changed after the failed replacement'}
  $target=Join-Path $root ('RIGMMaker-validated-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.exe')
  [IO.File]::Move($stage,$target,$false)
}
if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash){throw 'Published executable differs from the verified build'}
$report=@{
  success=$true;utc=[DateTime]::UtcNow.ToString('o');source=$exe;sha256=$hash;launchExecutable=$target
  rootReplaced=(-not $alias);aliasUsed=$alias;replacementFailureReason=$reason
  originalBackup=$backup;originalSha256=$oldHash;nativeGuiResults=[IO.Path]::GetFullPath($GuiResults)
  userApplicationsStopped=$false;humanDesktopVerification=$false
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8BOM
$report | ConvertTo-Json -Depth 8
