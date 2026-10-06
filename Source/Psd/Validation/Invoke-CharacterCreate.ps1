param([Parameter(Mandatory=$true)][string]$ExecutablePath,[ValidateSet('Debug','Release')][string]$Configuration='Release')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$root=Join-Path $env:TEMP ('RIGMMaker-CreateCheck-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Characters') | Out-Null
'{"owner":"RIGMMaker.GuiValidation.v1"}' | Set-Content -LiteralPath (Join-Path $root 'gui-validation-owner.json') -Encoding UTF8
$exe=[IO.Path]::GetFullPath($ExecutablePath)
$result=Join-Path $repo ('Win64\Validation\PsdStudio\character-create-'+$Configuration.ToLower()+'.json')
$process=Start-Process -FilePath $exe -ArgumentList @('--data-root',('"'+$root+'"'),'--verify-character-create',('"'+$result+'"')) -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(55); $captured=@{}
while(-not $process.HasExited){
 $requestPath=$result+'.capture-request.json'
 if(Test-Path -LiteralPath $requestPath){
  $request=$null
  try { $request=Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch [IO.IOException] { }
  if($null -ne $request -and $request.pid -eq $process.Id -and -not $captured.ContainsKey($request.token)){
   & (Join-Path $PSScriptRoot 'Capture-OwnedWindow.ps1') -ProcessId $process.Id -Path ($result+$request.stage+'.png')
   $request.token | Set-Content -LiteralPath ($result+'.capture-ack.txt') -Encoding UTF8
   $captured[$request.token]=$true
  }
 }
 if([DateTime]::UtcNow -gt $deadline){throw ('Owned validation remains active; keep its work root: '+$process.Id+' '+$root)}
 Start-Sleep -Milliseconds 100
}
$process.WaitForExit()
if($process.ExitCode -ne 0){if(Test-Path -LiteralPath ($result+'.error.txt')){Get-Content -LiteralPath ($result+'.error.txt') -Encoding UTF8};throw 'Character creation flow validation failed'}
$checks=@(Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json)
if($checks.Count -ne 18 -or $captured.Count -ne 2){throw 'Missing character creation checks or native screenshots'}
@{configuration=$Configuration;root=$root;result=$result;executable=$exe;exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;normalExit=$true;checks=$checks.Count;screenshots=$captured.Count;method='owned native controls and events; no user files touched'} | ConvertTo-Json | Tee-Object -FilePath ($result+'.metadata.json')
