param([Parameter(Mandatory)][string]$Candidate,[string]$DataRoot='D:\Users\take6\RIGMMaker')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$original=Join-Path $DataRoot 'Characters\blonde-android-20261005.psdchar'
$before=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
$assets=@(Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Characters') -File|Where-Object {$_.Extension -in @('.png','.psd')}|ForEach-Object {@{path=$_.FullName;hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
$work=Join-Path $DataRoot ('Work\Registration-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -LiteralPath $original -Destination (Join-Path $work 'previous-original.psdchar')
$inputCopy=Join-Path $work 'editing-copy.psdchar';Copy-Item -LiteralPath $original -Destination $inputCopy
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Manifest([string]$Path){$zip=[IO.Compression.ZipFile]::OpenRead($Path);try{$r=[IO.StreamReader]::new($zip.GetEntry('manifest.json').Open());try{return ($r.ReadToEnd()|ConvertFrom-Json)}finally{$r.Dispose()}}finally{$zip.Dispose()}}
$sourceManifest=Manifest $original;$candidateManifest=Manifest $Candidate
if($sourceManifest.id -ne $candidateManifest.id -or $sourceManifest.name -ne $candidateManifest.name){throw 'Candidate belongs to another character'}
$funName=[string][char]0x697D+[char]0x3057+[char]0x307F
$fun=$candidateManifest.settings.expressions.PSObject.Properties[$funName].Value
$reference=$candidateManifest.settings.motionReference
if(-not $fun -or -not $reference -or -not $candidateManifest.production.checked -or -not $candidateManifest.production.ready){throw 'Validated fun and measured-reference candidate required'}
function Call([string]$Name,[hashtable]$Payload=@{}){
 $c=[IO.Pipes.NamedPipeClientStream]::new('.',$script:pipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 try{$c.Connect(5000);$c.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
  $q=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString('N');command=$Name;args=$Payload}|ConvertTo-Json -Depth 24 -Compress
  $b=[Text.Encoding]::UTF8.GetBytes($q);$c.Write($b,0,$b.Length);$c.Flush();$buffer=New-Object byte[] 65536;$t=$c.ReadAsync($buffer,0,$buffer.Length)
  if(-not $t.Wait(45000)){throw ('Pipe timeout: '+$Name)}
  $reply=[Text.Encoding]::UTF8.GetString($buffer,0,$t.Result)|ConvertFrom-Json
  if(-not $reply.ok){throw ($Name+': '+$reply.error.message)};return $reply.data
 }finally{$c.Dispose()}
}
function EditArgs([hashtable]$Extra=@{}){$s=Call 'psd-status';$p=@{sessionId=$s.sessionId;revision=$s.revision};foreach($k in $Extra.Keys){$p[$k]=$Extra[$k]};return $p}
$exe=Join-Path $repo 'Win64\Validation\IntegratedPsd\Release\RIGMWizard.exe'
$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$DataRoot+'"')) -WindowStyle Hidden -PassThru
$closed=$false
try{
 $connection=Join-Path $DataRoot ('Exchange\workspace-'+$process.Id+'.json');$until=[DateTime]::UtcNow.AddSeconds(15)
 while(-not(Test-Path -LiteralPath $connection)){if($process.HasExited -or [DateTime]::UtcNow -gt $until){throw 'Registration application did not start'};Start-Sleep -Milliseconds 100}
 $script:pipeName=(Get-Content -LiteralPath $connection -Encoding UTF8 -Raw|ConvertFrom-Json).commandPipe
 [void](Call 'psd-open' (EditArgs @{path=$inputCopy}))
 [void](Call 'psd-set-expression' (EditArgs @{name=$funName;preset=$fun}))
 [void](Call 'psd-set-motion-reference' (EditArgs @{reference=$reference}))
 $checked=Call 'psd-check-production' (EditArgs)
 if(-not $checked.readyForScript){throw 'Working copy did not pass current production rules'}
 if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $before){throw 'Original changed externally; refusing replacement'}
 [void](Call 'psd-save' (EditArgs @{path=$original}))
 [void](Call 'psd-open' (EditArgs @{path=$original}))
 $reopened=Call 'psd-status';if(-not $reopened.readyForScript){throw 'Reopened registration is not complete'}
 foreach($asset in $assets){if((Get-FileHash -LiteralPath $asset.path -Algorithm SHA256).Hash -ne $asset.hash){throw ('Input asset changed: '+$asset.path)}}
 $after=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
 $result=@{path=$original;beforeHash=$before;afterHash=$after;backup=(Join-Path $work 'previous-original.psdchar');readyForScript=$true;reference=$reference;expression=$funName;newImagesGenerated=$false;inputAssets=$assets;production=$reopened.production}
 $result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $work 'registration-result.json') -Encoding UTF8
 $result|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $repo 'Win64\Validation\PsdStudio\registration-resumed.json') -Encoding UTF8
 [void]$process.CloseMainWindow();if(-not $process.WaitForExit(15000)){throw 'Registration process remains open; preserve it'};$closed=$true
 $result|ConvertTo-Json -Depth 20
}finally{if(-not $closed -and -not $process.HasExited){Write-Warning ('Owned process '+$process.Id+' remains active; backup: '+$work)}}
