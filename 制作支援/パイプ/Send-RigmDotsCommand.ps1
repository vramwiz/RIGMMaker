param(
    [Parameter(Mandatory=$true)][string]$ConnectionFile,
    [Parameter(Mandatory=$true)][string]$Command,
    [string]$ArgsJson = '{}',
    [string]$RequestId = ([guid]::NewGuid().ToString()),
    [int]$TimeoutMs = 15000,
    [switch]$Raw
)
$ErrorActionPreference = 'Stop'
$connection = Get-Content -LiteralPath $ConnectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($connection.protocol -ne 'rigm-maker-dots/1') { throw 'Unsupported discovery protocol.' }
if ($connection.accessMode -ne 'appcontainer-test') {
    $server = Get-Process -Id $connection.processId -ErrorAction SilentlyContinue
    if ($null -eq $server -or $server.ProcessName -ne 'RIGMMaker') {
        throw 'stale_connection: 対象アプリは終了しています。起動中フォームのconnection.jsonを指定してください。'
    }
}
$arguments = ConvertFrom-Json -InputObject $ArgsJson -AsHashtable
if ($arguments -isnot [Collections.IDictionary]) { throw 'ArgsJson must be an object.' }
$requestObject = @{version=1; id=$RequestId; command=$Command; args=$arguments}
if ($connection.requiresAccessToken) { $requestObject.accessToken = $connection.accessToken }
$request = $requestObject | ConvertTo-Json -Depth 32 -Compress
$utf8 = [Text.UTF8Encoding]::new($false,$true)
$bytes = $utf8.GetBytes($request + "`n")
if ($bytes.Length -gt $connection.maxFrameBytes) { throw 'Request exceeds maxFrameBytes.' }
$pipe = [IO.Pipes.NamedPipeClientStream]::new('.', $connection.pipeName, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
$cancel = [Threading.CancellationTokenSource]::new()
$reply = [IO.MemoryStream]::new()
try {
    try { $pipe.Connect($TimeoutMs) }
    catch {
        $cause = $_.Exception
        while ($cause.InnerException) { $cause = $cause.InnerException }
        if (($cause.HResult -band 0xffff) -eq 5) {
            throw ('pipe_access_denied (0x80070005): パイプを開く権限がありません。失敗したDots側と同じ実行環境でSource/Diagnostics/DotsCodexProbe/Diagnose-PipeAccess.ps1を実行してください。接続先: '+$connection.pipeName)
        }
        throw
    }
    $write = $pipe.WriteAsync($bytes,0,$bytes.Length,$cancel.Token)
    if (-not $write.Wait($TimeoutMs)) { throw 'Pipe write timed out.' }
    $write.GetAwaiter().GetResult()
    $buffer = [byte[]]::new(16384)
    $complete = $false
    while (-not $complete) {
        $read = $pipe.ReadAsync($buffer,0,$buffer.Length,$cancel.Token)
        if (-not $read.Wait($TimeoutMs)) { throw 'Pipe read timed out.' }
        $count = $read.GetAwaiter().GetResult()
        if ($count -eq 0) { throw 'Connection closed before LF.' }
        for ($i=0; $i -lt $count; $i++) {
            if ($buffer[$i] -eq 10) { $complete=$true; break }
            $reply.WriteByte($buffer[$i])
            if ($reply.Length -ge $connection.maxFrameBytes) { throw 'Response exceeds maxFrameBytes.' }
        }
    }
    $text = $utf8.GetString($reply.ToArray())
    $response = $text | ConvertFrom-Json
    if ($response.version -ne 1 -or $response.id -cne $RequestId) { throw 'Response version/id mismatch.' }
    if ($Raw) { $text } else { $response }
} finally {
    $cancel.Cancel()
    $pipe.Dispose()
    $reply.Dispose()
    $cancel.Dispose()
}
