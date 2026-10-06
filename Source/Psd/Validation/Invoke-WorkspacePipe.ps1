param([ValidateSet('Debug','Release')][string]$Configuration='Debug',[string]$DataRoot='D:\Users\take6\RIGMMaker')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-WorkspaceCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') -Force | Out-Null
$original=Join-Path $DataRoot 'Characters\blonde-android-20261005.psdchar'
$originalHash=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
$fixture=Join-Path $root 'Characters\fixture.psdchar'
Copy-Item -LiteralPath $original -Destination $fixture
& (Join-Path $PSScriptRoot 'Reset-ValidationFixture.ps1') -Fixture $fixture
$fixtureHash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
$checks=[Collections.Generic.List[string]]::new()
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message};$checks.Add($Message)}
function Call([string]$Name,[hashtable]$Payload=@{},[bool]$ExpectError=$false){
 $client=[IO.Pipes.NamedPipeClientStream]::new('.',$script:pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{
  $client.Connect(5000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $request=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$Name;args=$Payload}|ConvertTo-Json -Depth 20 -Compress
  $bytes=[Text.Encoding]::UTF8.GetBytes($request);$client.Write($bytes,0,$bytes.Length);$client.Flush()
  $buffer=New-Object byte[] 65536;$read=$client.ReadAsync($buffer,0,$buffer.Length)
  if(-not $read.Wait(15000)){throw ('Pipe timeout: '+$Name)}
  $reply=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result)|ConvertFrom-Json
  if($reply.ok -eq $ExpectError){throw ('Unexpected response for '+$Name+': '+($reply|ConvertTo-Json -Depth 8 -Compress))}
  if($ExpectError){return $reply.error};return $reply.data
 }finally{$client.Dispose()}
}
function PsdArgs([hashtable]$Extra=@{}){
 $s=Call 'psd-status';$a=@{sessionId=$s.sessionId;revision=$s.revision};foreach($k in $Extra.Keys){$a[$k]=$Extra[$k]};return $a
}
function MovieArgs([hashtable]$Extra=@{}){
 $s=Call 'movie-status';$a=@{projectId=$s.projectId;revision=$s.revision};foreach($k in $Extra.Keys){$a[$k]=$Extra[$k]};return $a
}
$exe=Join-Path $repo ('Win64\Validation\IntegratedPsd\'+$Configuration+'\RIGMWizard.exe')
$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"')) -WindowStyle Hidden -PassThru
$closed=$false
try{
 $connection=Join-Path $root ('Exchange\workspace-'+$process.Id+'.json')
 $deadline=[DateTime]::UtcNow.AddSeconds(12)
 while(-not(Test-Path -LiteralPath $connection)){
  if($process.HasExited -or [DateTime]::UtcNow -gt $deadline){throw 'Workspace connection was not published'}
  Start-Sleep -Milliseconds 100
 }
 $info=Get-Content -LiteralPath $connection -Encoding UTF8 -Raw|ConvertFrom-Json;$script:pipeName=$info.commandPipe
 $s=Call 'app-status';Check ($s.page -eq 'home' -and $s.openDocuments -eq 0) 'home pipe does not create a movie session'
 $lib=Call 'app-library';Check ($lib.characters.Count -eq 1 -and -not $lib.characters[0].readyForScript) 'incomplete PSD remains in editable library'
 [void](Call 'app-switch-page' @{page='create'});$movie=Call 'movie-status';$id=$movie.projectId
 [void](Call 'movie-update-project' (MovieArgs @{title='Common pipe validation'}))
 $path=Join-Path $root 'saved-work.rigmovie';[void](Call 'movie-save' (MovieArgs @{path=$path}))
 [void](Call 'app-switch-page' @{page='preview';propertyPage='acting'})
 $s=Call 'app-status';Check ($s.page -eq 'preview' -and $s.movie.projectId -eq $id) 'create and movie routes share the same session'
 [void](Call 'app-open-work' @{path=$path});$s=Call 'movie-status';Check ($s.projectId -eq $id -and $s.title -eq 'Common pipe validation') 'saved work reopens through common pipe'
 [void](Call 'app-edit-character' @{path=$fixture});$psd=Call 'psd-status'
 [void](Call 'psd-open' (PsdArgs @{path=$fixture}))
 [void](Call 'psd-set-info' @{sessionId=$psd.sessionId;revision='0';name='must reject'} $true)
 Check ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -eq $fixtureHash) 'stale PSD mutation preserves saved bytes'
 [void](Call 'app-edit-character' @{path=(Join-Path $env:TEMP 'outside.psdchar')} $true)
 Check $true 'character paths outside the data root are rejected'
 $psd=Call 'psd-status';$fun=$psd.settings.expressions.PSObject.Properties.Value|Where-Object {$_.variants.choice -contains '*笑顔閉じ'}|Select-Object -First 1
 if(-not $fun){throw 'Existing joy parts are unavailable'}
 $fun=$fun|ConvertTo-Json -Depth 15|ConvertFrom-Json
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($fixture)
 try{$reader=[IO.StreamReader]::new($zip.GetEntry('manifest.json').Open());try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}}finally{$zip.Dispose()}
 function FindLayer($nodes,[string]$Id){foreach($n in $nodes){if($n.id -eq $Id){return $n};$f=FindLayer $n.children $Id;if($f){return $f}}}
 foreach($variant in $fun.variants){
  $group=$psd.settings.groups|Where-Object {$_.id -eq $variant.groupId};$groupLayer=FindLayer $manifest.layers $group.id
  $name=$null
  if($group.id -eq $psd.settings.animation.lipSync.groupId){$name='*'+[char]0x3042}
  elseif($groupLayer.children.name -contains ('*'+[char]0x30CF+[char]0x30FC+[char]0x30C8)){$name='*'+[char]0x30CF+[char]0x30FC+[char]0x30C8}
  elseif($group.name -eq ([string][char]0x4F53)){$name='*'+[char]0x901A+[char]0x5E38}
  if($name){$part=$groupLayer.children|Where-Object {$_.name -eq $name}|Select-Object -First 1;if(-not $part){throw ('Missing existing part '+$name)};$variant.partId=$part.id;$variant.choice=$name}
 }
 $funName=[string][char]0x697D+[char]0x3057+[char]0x307F
 [void](Call 'psd-set-expression' (PsdArgs @{name=$funName;preset=$fun}))
 # Measured from the actual 1152x2048 neutral source, not normalized fixture fractions.
 $reference=@{schemaVersion=1;source='ai';faceBounds=@{left=475;top=290;right=688;bottom=454};neck=@{x=579;y=467};screenLeftShoulder=@{x=410;y=547};screenRightShoulder=@{x=742;y=547};upperBodyBottomY=850}
 [void](Call 'psd-set-motion-reference' (PsdArgs @{reference=$reference}))
 $psd=Call 'psd-check-production' (PsdArgs);Check $psd.readyForScript 'existing parts and measured motion references satisfy production checks'
 [void](Call 'psd-save' (PsdArgs))
 [void](Call 'psd-set-view' (PsdArgs @{expression=$funName;motion='none';autoBlink=$false;hasPhoneme=$false}))
 $funImage=Join-Path $root 'Work\fun.png';[void](Call 'psd-render-file' (PsdArgs @{path=$funImage;seconds=0}))
 Check ((Get-Item -LiteralPath $funImage).Length -gt 60000) 'large rendered image transfers as a data-root file reference'
 [void](Call 'psd-add-layer-file' (PsdArgs @{path=$funImage;groupId='invalid';name='invalid'}) $true)
 Check $true 'invalid layer registration is rejected'
 [void](Call 'app-register-character' @{path=$fixture;name='Registered copy'})
 Check ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -ne $fixtureHash) 'fixture changes are confined to the owned test root'
 $lib=Call 'app-library';Check ($lib.characters.Count -eq 2) 'common registration publishes a new package'
 $sourceHash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
 [void](Call 'app-register-character' @{path=$fixture;name='Another copy'})
 Check ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -eq $sourceHash) 'registration with a new name preserves its input package'
 [void](Call 'app-switch-page' @{page='home'});Check ((Call 'app-status').page -eq 'home') 'pipe navigation returns home'
 Check ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -eq $originalHash) 'user original remains unchanged'
 $process.Refresh();[void]$process.CloseMainWindow()
 if(-not $process.WaitForExit(15000)){throw 'Validation app remains open; preserve it and report'}
 $closed=$true;Check ($process.ExitCode -eq 0) 'validation app exits normally'
 Check (-not(Test-Path -LiteralPath $connection)) 'closed connection metadata is moved into owned recovery jobs'
 $result=@{configuration=$Configuration;root=$root;normalExit=$true;checks=$checks;funImage=$funImage;reference=$reference}
 $out=Join-Path $repo ('Win64\Validation\PsdStudio\workspace-pipe-'+$Configuration.ToLower()+'.json')
 $result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $out -Encoding UTF8
 $result|ConvertTo-Json -Depth 12
}finally{
 if(-not $closed -and -not $process.HasExited){Write-Warning ('Owned validation process '+$process.Id+' remains active at '+$root+'; do not delete or overwrite it')}
}
