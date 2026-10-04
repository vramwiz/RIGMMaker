#requires -Version 7.0
param([Parameter(Mandatory)][string]$TaskDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot;$TaskDirectory=[IO.Path]::GetFullPath($TaskDirectory)
if(-not $TaskDirectory.StartsWith((Join-Path $root 'Win64\Validation\ImageTransfer-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected task directory'}
$deployment=[IO.File]::ReadAllText((Join-Path $TaskDirectory 'deployment.json'))|ConvertFrom-Json -AsHashtable
if((Get-FileHash -LiteralPath $deployment.executable).Hash -ne $deployment.validatedReleaseSha256){throw 'Deployed product hash differs'}
$deployed=[IO.File]::ReadAllText((Join-Path $TaskDirectory 'Actual-Deployed\run.json'))|ConvertFrom-Json -AsHashtable
if(-not $deployed.success -or -not $deployed.closedNormally){throw 'Deployed product verification is incomplete'}
$targets=[Collections.Generic.List[object]]::new()
function Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function AddTarget([string]$Path){
  $Path=[IO.Path]::GetFullPath($Path)
  if(-not $Path.StartsWith($TaskDirectory+'\',[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith((Join-Path $TaskDirectory 'Preserved\'),[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith((Join-Path $TaskDirectory 'Build\Release\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Protected cleanup target'}
  if(-not (Test-Path -LiteralPath $Path)){return}
  $item=Get-Item -LiteralPath $Path -Force
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Cleanup will not traverse reparse points'}
  $entries=if($item.PSIsContainer){@(Get-ChildItem -LiteralPath $Path -Recurse -Force -File)}else{@($item)}
  $files=@(foreach($file in $entries){if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Unexpected reparse file'};@{relative=if($item.PSIsContainer){[IO.Path]::GetRelativePath($Path,$file.FullName)}else{$file.Name};sha256=Sha $file.FullName;bytes=$file.Length}})
  $targets.Add(@{path=$Path;directory=$item.PSIsContainer;files=$files;bytes=($files|Measure-Object bytes -Sum).Sum})
}
foreach($runDirectory in Get-ChildItem -LiteralPath $TaskDirectory -Directory -Filter 'Actual-*'){
  $run=[IO.File]::ReadAllText((Join-Path $runDirectory.FullName 'run.json'))|ConvertFrom-Json -AsHashtable
  if(-not $run.owned -or -not $run.closedNormally){throw 'Only closed owned runs may be cleaned'}
  $running=Get-Process -Id $run.pid -ErrorAction SilentlyContinue
  if($running -and $running.Path -eq $run.executable){throw 'Owned test process is still running'}
  foreach($folder in @('Settings','Library','Pipes','transfer-fixture.assets','ReparseTarget')){AddTarget (Join-Path $runDirectory.FullName $folder)}
  foreach($movie in Get-ChildItem -LiteralPath $runDirectory.FullName -File -Filter '*.rigmovie'){
    $json=[IO.File]::ReadAllText($movie.FullName)|ConvertFrom-Json
    if($json.format -ne 'RIGM-MOVIE'){throw 'Unexpected fixture project format'}
    AddTarget $movie.FullName
  }
}
AddTarget (Join-Path $TaskDirectory 'Dcu');AddTarget (Join-Path $TaskDirectory 'Build\Debug')
$planPath=Join-Path $TaskDirectory 'cleanup-plan.json';$nativePath=Join-Path $TaskDirectory 'cleanup-native-result.json'
@{root=$root;targets=@($targets);method='force recycle only; preserve source, results, screenshots, Release product and original root EXE'}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $planPath -Encoding utf8BOM
$helper=[IO.File]::ReadAllText((Join-Path $root 'Win64\Validation\CritiqueProduction\cleanup-helper.json'))|ConvertFrom-Json
if((Sha $helper.nativeExe) -ne $helper.sha256){throw 'Native recycle helper changed'}
foreach($target in $targets){foreach($file in $target.files){$source=if($target.directory){Join-Path $target.path $file.relative}else{$target.path};if((Sha $source) -ne $file.sha256){throw 'Cleanup source changed after planning'}}}
& $helper.nativeExe $planPath $nativePath
$native=[IO.File]::ReadAllText($nativePath)|ConvertFrom-Json -AsHashtable
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$recycleRoot=Join-Path 'D:\$Recycle.Bin' $sid
$verified=@(foreach($target in $targets){
  $item=@($native.items|Where-Object sourcePath -eq $target.path|Where-Object recycleItemReturned|Select-Object -Last 1)
  $location=if($item.Count){$item[0].recycleLocation}else{''};$ok=$false;$metadata=''
  if($location -and $location.StartsWith($recycleRoot+'\',[StringComparison]::OrdinalIgnoreCase)){
    $metadata=Join-Path (Split-Path $location) ((Split-Path $location -Leaf) -replace '^\$R','$$I')
    if((Test-Path -LiteralPath $metadata) -and (Test-Path -LiteralPath $location) -and -not (Test-Path -LiteralPath $target.path)){
      $bytes=[IO.File]::ReadAllBytes($metadata);$version=[BitConverter]::ToInt64($bytes,0);$offset=if($version -eq 2){28}else{24}
      $original=[Text.Encoding]::Unicode.GetString($bytes,$offset,$bytes.Length-$offset).TrimEnd([char]0);$ok=$original -eq $target.path
      foreach($file in $target.files){$payload=if($target.directory){Join-Path $location $file.relative}else{$location};if(-not (Test-Path -LiteralPath $payload) -or (Sha $payload) -ne $file.sha256){$ok=$false}}
    }
  }
  @{path=$target.path;bytes=$target.bytes;recycleLocation=$location;recycleMetadata=$metadata;recoverableVerified=$ok}
})
$success=$native.success -and @($verified|Where-Object {-not $_.recoverableVerified}).Count -eq 0
$report=@{success=$success;count=$verified.Count;bytes=($verified|Measure-Object bytes -Sum).Sum;accountSid=$sid;items=$verified;permanentDeleteFallback=$false;method='IFileOperation force recycle; original path metadata and every payload SHA-256 verified';restore='Use Windows Recycle Bin Restore; exact metadata and payload paths are recorded'}
$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $TaskDirectory 'cleanup-result.json') -Encoding utf8BOM
@{success=$success;count=$report.count;bytes=$report.bytes;permanentDeleteFallback=$false}|ConvertTo-Json
if(-not $success){throw 'Recycle verification incomplete; no permanent-delete fallback attempted'}
