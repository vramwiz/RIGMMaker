param([Parameter(Mandatory=$true)][string]$ExecutablePath,[ValidateSet('Debug','Release')][string]$Configuration='Release',[switch]$RigmOnly)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-CreateCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') | Out-Null
$sourceRoot=Join-Path $env:TEMP ('RIGMMaker-DropCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sourceRoot | Out-Null
$fixture=Join-Path $sourceRoot 'fixture.psdchar'
Copy-Item -LiteralPath 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar' -Destination $fixture
$rigFixture=Get-ChildItem -LiteralPath 'D:\Users\take6\RIGMMaker\RIGM' -Filter *.rigm -File | Select-Object -First 1
if($null -eq $rigFixture){throw 'RIGM fixture missing'}
Copy-Item -LiteralPath $rigFixture.FullName -Destination (Join-Path $sourceRoot 'fixture.rigm')
@{owner='RIGMMaker.GuiValidation.v1';fixturePath=$fixture} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$exe=[IO.Path]::GetFullPath($ExecutablePath)
$kind='character-create-'; if($RigmOnly){$kind='character-rigm-'}
$result=Join-Path $repo ('Win64\Validation\PsdStudio\'+$kind+$Configuration.ToLower()+'.json')
$arguments=@('--data-root',('"'+$root+'"'),'--verify-character-create',('"'+$result+'"'))
if($RigmOnly){$arguments+='--rigm-only'}
$process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(150); $captured=@{}
while(-not $process.HasExited){
 $requestPath=$result+'.capture-request.json'
 if(Test-Path -LiteralPath $requestPath){
  $request=$null
  try { $request=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch [IO.IOException] { }
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   # 所有EXEの短い読み込みロックと競合したら次のループで再送する。
   try { $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8 -ErrorAction Stop }
   catch [IO.IOException] { Start-Sleep -Milliseconds 25; continue }
   $captured[$request.token]=$true
  }
 }
 if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation remains active; keep its work root: '+$process.Id+' '+$root)}
 Start-Sleep -Milliseconds 100
}
$process.WaitForExit()
if($process.ExitCode -ne 0){if(Test-Path -LiteralPath ($result+'.error.txt')){Get-Content -LiteralPath ($result+'.error.txt') -Encoding UTF8};throw 'Character creation flow validation failed'}
$checks=@(Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json)
$minimumChecks=40; $expectedCaptures=9; if($RigmOnly){$minimumChecks=14;$expectedCaptures=5}
if($checks.Count -lt $minimumChecks -or $captured.Count -ne $expectedCaptures){throw 'Missing character creation checks or native screenshots'}
@{configuration=$Configuration;root=$root;sourceRoot=$sourceRoot;result=$result;executable=$exe;exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;normalExit=$true;checks=$checks.Count;screenshots=$captured.Count;method='owned native controls and events; no user files touched'} | ConvertTo-Json | Tee-Object -FilePath ($result+'.metadata.json')
