param([Parameter(Mandatory)][string]$Command,[string]$ArgsJson='{}',[string]$ArgsFile,[string]$OutputFile)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$connectionPath='C:\Users\zan12\Documents\RIGMMaker\Exchange\workspace-6936.json'
$connection=Get-Content -LiteralPath $connectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$live=Get-Process -Id $connection.pid -ErrorAction Stop
if($live.Path -ne 'D:\DelphiProg\RIGMMaker\RIGMMaker.exe'){throw 'Unexpected live app'}
if($ArgsFile){$ArgsJson=Get-Content -LiteralPath $ArgsFile -Raw -Encoding UTF8}
$payload=$ArgsJson | ConvertFrom-Json
$requestId=[guid]::NewGuid().ToString('N')
$envelope=@{schemaVersion=1;requestId=$requestId;command=$Command;args=$payload}
$client=[IO.Pipes.NamedPipeClientStream]::new('.',$connection.commandPipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
try {
 $client.Connect(5000)
 $client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
 $bytes=[Text.Encoding]::UTF8.GetBytes(($envelope | ConvertTo-Json -Depth 60 -Compress))
 $client.Write($bytes,0,$bytes.Length)
 $client.Flush()
 $memory=[IO.MemoryStream]::new()
 try {
  do {
   $buffer=[byte[]]::new(65536)
   $read=$client.ReadAsync($buffer,0,$buffer.Length)
   if(-not $read.Wait(20000)){throw ('Pipe timeout: '+$Command)}
   if($read.Result -eq 0){throw 'Unexpected pipe closure'}
   $memory.Write($buffer,0,$read.Result)
   if($memory.Length -gt 4194304){throw 'Unexpected large response'}
  } until ($client.IsMessageComplete)
  $reply=[Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json
 } finally {$memory.Dispose()}
 if($reply.requestId -ne $requestId){throw 'Response request mismatch'}
 if(-not $reply.ok){throw ($reply.error | ConvertTo-Json -Depth 20 -Compress)}
 if($OutputFile){$reply.data | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $OutputFile -Encoding UTF8}
 $reply.data
} finally {$client.Dispose()}
