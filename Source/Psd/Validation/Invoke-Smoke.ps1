param([string]$DataRoot = 'D:\Users\take6\RIGMMaker', [string]$Executable = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$exe = Join-Path $repoRoot 'Win64\Validation\PsdStudio\Release\PsdStudio.exe'
if ($Executable) { $exe = [IO.Path]::GetFullPath($Executable) }
$snapshot = Join-Path $repoRoot 'Win64\Validation\PsdStudio\studio-smoke.png'
$process = Start-Process -FilePath $exe -ArgumentList @('--smoke', $snapshot, '--root', $DataRoot) -WindowStyle Hidden -PassThru
$connection = $null
for ($attempt = 0; $attempt -lt 100; $attempt++) {
  $candidate = Get-ChildItem -LiteralPath (Join-Path $DataRoot 'Exchange') -Filter "psd-$($process.Id)-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($candidate) { $connection = Get-Content -LiteralPath $candidate.FullName -Raw | ConvertFrom-Json; break }
  Start-Sleep -Milliseconds 100
}
if (-not $connection) { throw 'Independent app did not publish a connection file' }
function Request([string]$Command, [hashtable]$CommandArgs) {
  $request = @{schemaVersion=1; requestId=[guid]::NewGuid().ToString(); command=$Command; args=$CommandArgs} | ConvertTo-Json -Depth 10 -Compress
  $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $connection.commandPipe, [IO.Pipes.PipeDirection]::InOut)
  try {
    $pipe.Connect(10000); $pipe.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
    $bytes = [Text.Encoding]::UTF8.GetBytes($request); $pipe.Write($bytes, 0, $bytes.Length); $pipe.Flush()
    $reply = [IO.MemoryStream]::new(); $buffer = [byte[]]::new(65536)
    try {
      do { $count = $pipe.Read($buffer, 0, $buffer.Length); if ($count -eq 0) { throw 'Pipe ended without response' }; $reply.Write($buffer, 0, $count) } while (-not $pipe.IsMessageComplete)
      return ([Text.Encoding]::UTF8.GetString($reply.ToArray()) | ConvertFrom-Json)
    } finally { $reply.Dispose() }
  } finally { $pipe.Dispose() }
}
$status = Request 'status' @{}
if (-not $status.ok -or $status.data.width -ne 1152 -or $status.data.height -ne 2048) { throw 'Unexpected registered character' }
$current = @{sessionId=$status.data.sessionId; revision=$status.data.revision}
$wrong = Request 'save' @{sessionId=$status.data.sessionId; revision='0'}
if ($wrong.ok) { throw 'Stale revision was accepted' }
$timeBefore = (Get-Item -LiteralPath $status.data.savedPath).LastWriteTimeUtc
$save = Request 'save' $current
if (-not $save.ok -or (Get-Item -LiteralPath $status.data.savedPath).LastWriteTimeUtc -ne $timeBefore) { throw 'Clean save rewrote package' }
$current.expression = '喜び'; $current.phoneme = 'a'; $current.hasPhoneme = $true; $current.motion = 'breathe'
$view = Request 'set-view' $current
if (-not $view.ok) { throw ('View failed: ' + $view.error.message) }
$output = 'Characters\blonde-android-20261005-fullhd-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.png'
$render = Request 'render-file' @{sessionId=$status.data.sessionId; revision=$status.data.revision; seconds=3.85; path=$output}
if (-not $render.ok) { throw ('Frame failed: ' + $render.error.message) }
if (-not $process.WaitForExit(15000) -or $process.ExitCode -ne 0) { throw 'Smoke app did not exit normally' }
if (-not (Test-Path -LiteralPath $snapshot)) { throw 'App-owned UI snapshot was not created' }
if (Test-Path -LiteralPath $candidate.FullName) { throw 'Live connection marker remained after normal exit' }
[pscustomobject]@{AppPid=$process.Id; Status=$true; StaleRevisionRejected=$true; CleanSaveUnchanged=$true; View=$true; FullHD=$render.data.path; UiSnapshot=$snapshot; NormalExit=$true; ConnectionRecovered=$true} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $repoRoot 'Win64\Validation\PsdStudio\smoke-result.json')
