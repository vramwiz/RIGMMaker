#requires -Version 7.0
param(
    [string]$PipeName,
    [string]$ConnectionFile,
    [Parameter(Mandatory=$true)][ValidateSet('status','schema','document','validate','switch-page','select-object','save','undo','redo','import-png','replace-png','import-psd','classify-layers','add-group','update-layer','move-layer','set-parent','delete-layer','verify-source','mark-complete','add-bone','update-bone','hide-bone','restore-bone','reset-bone','bind-part','generate-mesh','set-mesh','set-vertices','delete-mesh','update-mesh','update-vertex','add-vertex','delete-vertex','set-triangles','set-weights','update-parameter','autofix','ignore-issue','request-fix','export','import','batch','movie-status','movie-schema','movie-project','movie-import-script','movie-update-project','movie-update-cue','movie-add-cue','movie-delete-cue','movie-move-cue','movie-update-speaker','movie-speakers-refresh','movie-speaker-list','movie-audio-generate','movie-job-status','movie-job-cancel','movie-job-retry','movie-timeline','movie-seek','movie-preview','movie-export','movie-save','movie-open','movie-undo','movie-redo','movie-play','movie-pause','movie-playback-audio','movie-open-ui','movie-assets-refresh','movie-assets','movie-waveform-refresh','movie-waveform','movie-preparation','movie-diagnostics-refresh','movie-produce','movie-production-status','movie-production-resume','movie-production-cancel','movie-workflow-status','movie-workflow-next','movie-workflow-back','movie-workflow-run','movie-composition-enable','movie-add-character','movie-update-character','movie-delete-character','movie-add-scene','movie-update-scene','movie-delete-scene','movie-move-scene','movie-resize-scene','movie-register-expression','movie-analyze-script','movie-update-subtitle','movie-update-dialogue','movie-composition-requests','movie-edit-begin','movie-edit-status','movie-edit-heartbeat','movie-edit-end','movie-edit-fail','movie-edit-release','movie-register-motion','movie-select-motion','movie-stop-motion','app-status','app-switch-page','app-library','app-register-character','app-open-work')][string]$Command,
    [string]$ArgsJson = '{}',
    [string]$ArgsFile,
    [ValidateRange(1,60000)][int]$TimeoutMs = 5000
)
$ErrorActionPreference = 'Stop'
function Invoke-RigmPipe([string]$TargetPipe, [string]$Name, [System.Collections.IDictionary]$Arguments) {
    $envelope = @{ schemaVersion=1; requestId=[guid]::NewGuid().ToString(); command=$Name; args=$Arguments }
    $payload = [Text.Encoding]::UTF8.GetBytes(($envelope | ConvertTo-Json -Depth 32 -Compress))
    if ($payload.Length -gt 60000) { throw 'Command exceeds 60000 UTF-8 bytes' }
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $TargetPipe, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    try {
    $client.Connect($TimeoutMs)
    $client.ReadMode = [IO.Pipes.PipeTransmissionMode]::Message
    $write = $client.WriteAsync($payload,0,$payload.Length)
    if (-not $write.Wait($TimeoutMs)) { throw 'Pipe write timed out' }
    $buffer = [byte[]]::new(65536)
    $read = $client.ReadAsync($buffer,0,$buffer.Length)
    if (-not $read.Wait($TimeoutMs)) { throw 'Pipe response timed out' }
    $received = $read.GetAwaiter().GetResult()
    if (($received -eq 0) -or (-not $client.IsMessageComplete)) { throw 'Incomplete pipe response' }
    $response = [Text.Encoding]::UTF8.GetString($buffer,0,$received) | ConvertFrom-Json
    if ($response.requestId -ne $envelope.requestId) { throw 'Response requestId mismatch' }
    if (-not $response.ok) { throw $response.error.message }
    return $response
    } finally { $client.Dispose() }
}
if ($ArgsFile) {
    if ($PSBoundParameters.ContainsKey('ArgsJson')) { throw 'Specify either ArgsJson or ArgsFile' }
    $ArgsJson = Get-Content -LiteralPath $ArgsFile -Raw -Encoding UTF8
}
$arguments = ConvertFrom-Json -InputObject $ArgsJson -AsHashtable
if ($arguments -isnot [System.Collections.IDictionary]) { throw 'ArgsJson must be a JSON object' }
if ($ConnectionFile) {
    $connection = Get-Content -LiteralPath $ConnectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $PipeName = if ($connection.commandPipe) { $connection.commandPipe } else { $connection.controlPipe }
}
if (-not $PipeName) { throw 'Specify ConnectionFile or PipeName' }
$statusResponse = Invoke-RigmPipe $PipeName 'status' @{}
$status = $statusResponse.data
$readOnly = @('status','schema','document','validate','export')
if ($Command.StartsWith('movie-')) {
    $movie = (Invoke-RigmPipe $PipeName 'movie-status' @{}).data
    if (-not $arguments.Contains('projectId')) { $arguments.projectId = $movie.projectId }
    if (-not $arguments.Contains('revision')) { $arguments.revision = $movie.revision }
} elseif ($Command.StartsWith('app-')) {
    # Workspace operations route through the common endpoint.
} elseif ($Command -notin $readOnly) {
    if (-not $arguments.Contains('documentId')) { $arguments.documentId = $status.documentId }
    if (-not $arguments.Contains('revision')) { $arguments.revision = $status.revision }
}
$common = @('status','document','validate','switch-page','save','undo','redo')
if ($ConnectionFile -and $status.pipes.routing -ne 'common-command' -and $Command -notin $common -and $Command -ne 'schema') {
    $PipeName = $status.pipes.pagePipe
    if (-not $PipeName) { throw 'Current page has no editing pipe' }
}
Invoke-RigmPipe $PipeName $Command $arguments | ConvertTo-Json -Depth 32
