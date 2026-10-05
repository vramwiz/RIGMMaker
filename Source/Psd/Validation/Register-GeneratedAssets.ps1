param([string]$DataRoot = 'D:\Users\take6\RIGMMaker')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$assetsPath = Join-Path $DataRoot 'Work\PsdGenerated-20261005'
$assets = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $assetsPath 'prepared-assets.json') -Raw | ConvertFrom-Json
$snapshot = Join-Path $repoRoot 'Win64\Validation\PsdStudio\studio-registered.png'
$exe = Join-Path $repoRoot 'Win64\Validation\PsdStudio\Release\PsdStudio.exe'
$process = Start-Process -FilePath $exe -ArgumentList @('--smoke', $snapshot, '--smoke-ms', '45000', '--root', $DataRoot) -WindowStyle Hidden -PassThru
$connection = $null
for ($attempt = 0; $attempt -lt 100; $attempt++) {
  $candidate = Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Exchange') -Filter "psd-$($process.Id)-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($candidate) { $connection = Get-Content -Encoding UTF8 -LiteralPath $candidate.FullName -Raw | ConvertFrom-Json; break }
  Start-Sleep -Milliseconds 100
}
if (-not $connection) { throw 'Independent app did not publish connection' }
function Request([string]$Command, [hashtable]$CommandArgs) {
  $request = @{schemaVersion=1; requestId=[guid]::NewGuid().ToString(); command=$Command; args=$CommandArgs} | ConvertTo-Json -Depth 16 -Compress
  $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $connection.commandPipe, [IO.Pipes.PipeDirection]::InOut)
  try {
    $pipe.Connect(10000); $pipe.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
    $bytes = [Text.Encoding]::UTF8.GetBytes($request); $pipe.Write($bytes,0,$bytes.Length); $pipe.Flush()
    $reply = [IO.MemoryStream]::new(); $buffer = [byte[]]::new(65536)
    try {
      do { $count = $pipe.Read($buffer,0,$buffer.Length); if ($count -eq 0) { throw 'Missing response' }; $reply.Write($buffer,0,$count) } while (-not $pipe.IsMessageComplete)
      $result = [Text.Encoding]::UTF8.GetString($reply.ToArray()) | ConvertFrom-Json
      if (-not $result.ok) { throw ($Command + ': ' + $result.error.message) }
      return $result.data
    } finally { $reply.Dispose() }
  } finally { $pipe.Dispose() }
}
$status = Request 'status' @{}
$status = Request 'open' @{sessionId=$status.sessionId; revision=$status.revision; path='Characters\blonde-android-20261005.psdchar'}
$eyes = $status.settings.animation.blink.groupId
$registered = @()
foreach ($asset in $assets) {
  $found = @($status.settings.assetHistory | Where-Object { $_.sha256 -eq $asset.sha256 })
  if ($found.Count -gt 0) { $registered += @{key=$asset.key; assetId=$found[0].assetId; reused=$true}; continue }
  $names = @{'eyes-left'='視線・画面左'; 'eyes-left-up'='視線・画面左上'; 'eyes-up'='視線・画面上'; 'eyes-right-up'='視線・画面右上'; 'eyes-right'='視線・画面右'; 'pose-side'='全身・横向き'; 'pose-back'='全身・後ろ向き'}
  $args = @{sessionId=$status.sessionId; revision=$status.revision; name=$names[$asset.key]; path=$asset.output; sha256=$asset.sha256; x=$asset.x; y=$asset.y; productionMethod=$asset.method; newDrawing=$true; visualState='pending-user-review'; rawSourcePath=$asset.source; rawSourceSha256=$asset.sourceSha256}
  if ($asset.key.StartsWith('eyes-')) { $args.groupId=$eyes; $args.gaze=$asset.key.Substring(5); $status=Request 'add-layer-file' $args }
  else { $args.kind='pose'; $status=Request 'add-nonfront-file' $args }
  $registered += @{key=$asset.key; assetId=$status.settings.assetHistory[-1].assetId; reused=$false}
}
$status = Request 'save' @{sessionId=$status.sessionId; revision=$status.revision}
$export = 'Characters\blonde-android-20261005-v2.psd'
if (-not (Test-Path -LiteralPath (Join-Path $DataRoot $export))) { $null = Request 'export-psd' @{sessionId=$status.sessionId; revision=$status.revision; path=$export} }
$previews = @()
$previewFolder = 'Work\PsdGenerated-20261005\Preview'
foreach ($gaze in @('front','left','left-up','up','right-up','right')) {
  $null = Request 'set-view' @{sessionId=$status.sessionId; revision=$status.revision; expression='通常'; gaze=$gaze; nonFrontId=''; motion='none'; autoBlink=$false; hasPhoneme=$false}
  $output = $previewFolder + '\' + $gaze + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.png'
  $previews += (Request 'render-file' @{sessionId=$status.sessionId; revision=$status.revision; seconds=0; path=$output}).path
}
foreach ($pose in $status.settings.nonFront) {
  $null = Request 'set-view' @{sessionId=$status.sessionId; revision=$status.revision; nonFrontId=$pose.id; expression='喜び'; hasPhoneme=$true; phoneme='a'; autoBlink=$true}
  $output = $previewFolder + '\pose-' + $pose.id + '.png'
  if (-not (Test-Path -LiteralPath (Join-Path $DataRoot $output))) { $previews += (Request 'render-file' @{sessionId=$status.sessionId; revision=$status.revision; seconds=3.9; path=$output}).path }
}
$null = Request 'set-view' @{sessionId=$status.sessionId; revision=$status.revision; nonFrontId=''; expression='通常'; gaze='front'; hasPhoneme=$false; autoBlink=$true; motion='breathe'}
if (-not $process.WaitForExit(55000) -or $process.ExitCode -ne 0) { throw 'App did not exit normally' }
[pscustomobject]@{AppPid=$process.Id; Character=$status.characterId; Package=$status.savedPath; Registered=$registered; Previews=$previews; GeneratedDrawings=7; VisualState='pending-user-review'; NormalExit=$true; ConnectionRecovered=(-not (Test-Path -LiteralPath $candidate.FullName))} | ConvertTo-Json -Depth 8 | Tee-Object -FilePath (Join-Path $repoRoot 'Win64\Validation\PsdStudio\generated-registration.json')
