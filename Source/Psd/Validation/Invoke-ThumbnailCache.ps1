param([Parameter(Mandatory=$true)][string]$ExecutablePath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-ThumbnailCache-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
@{owner='RIGMMaker.ThumbnailCache.Validation.v1'} | ConvertTo-Json | Set-Content (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$source='D:\Users\take6\RIGMMaker'
$sources=@('Characters\blonde-android-20261005.psdchar','RIGM\character-5F644440-BD54-4F76-A1C2-91E152D6516D.rigm','RIGM\character-701CDB41-B20C-40F1-82D3-FCC623EF6C3F.rigm')
$hashes=@{}
foreach($f in $sources){$p=Join-Path $source $f;$hashes[$f]=(Get-FileHash $p).Hash;$dest=Join-Path $root $f;New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null;Copy-Item -LiteralPath $p -Destination $dest}
$output=Join-Path $repo 'Win64\Validation\ThumbnailCache';New-Item -ItemType Directory -Path $output -Force | Out-Null
$result=Join-Path $output 'thumbnail-cache.json'
$exe=[IO.Path]::GetFullPath($ExecutablePath)
function Read-CaptureRequest([string]$Path){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
 try {$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true);try {$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}} finally {$stream.Dispose()}
}
for($phase=0;$phase -lt 2;$phase++){
 $flag='--verify-thumbnail-cache';if($phase -eq 1){$flag='--verify-thumbnail-cache-reopen'}
 $process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--settings-dir',('"'+$root+'"'),$flag,('"'+$result+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTime]::UtcNow.AddSeconds(90);$captured=@{}
 while(-not $process.HasExited){
  $requestPath=$result+'.capture-request.json'
  if(Test-Path -LiteralPath $requestPath){
   $request=$null;try {$request=Read-CaptureRequest $requestPath} catch [IO.IOException] {}
   if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
    & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
    try {$request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop} catch [IO.IOException] {Start-Sleep -Milliseconds 25;continue}
    $captured[$request.token]=$true
   }
  }
  if([DateTime]::UtcNow -gt $deadline){throw ('Owned cache check still running; retain PID/root: '+$process.Id+' '+$root)}
  Start-Sleep -Milliseconds 50
 }
 $process.WaitForExit()
 if($process.ExitCode -ne 0){Get-Content ($result+'.error.txt') -Encoding UTF8 -ErrorAction SilentlyContinue;throw 'Owned cache verification failed'}
 $expected=2;if($phase -eq 1){$expected=1};if($captured.Count -ne $expected){throw 'Owned cache captures missing'}
}
foreach($f in $sources){if((Get-FileHash (Join-Path $source $f)).Hash -ne $hashes[$f]){throw 'Original material changed externally'}}
$cold=Get-Content $result -Raw -Encoding UTF8 | ConvertFrom-Json
$warm=Get-Content ($result+'.reopened.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($cold.checks.Count -lt 14 -or $warm.checks.Count -lt 6 -or $warm.stats.packageReads -ne 0){throw 'Cache checks incomplete'}
@{root=$root;executable=$exe;exeHash=(Get-FileHash $exe).Hash;normalExit=$true;coldChecks=$cold.checks.Count;restartChecks=$warm.checks.Count;coldTimesMs=$cold.timesMs;restartTimesMs=$warm.timesMs;restartStats=$warm.stats;originalHashes=$hashes;captures=3} | ConvertTo-Json -Depth 6 | Tee-Object -FilePath ($result+'.metadata.json')
