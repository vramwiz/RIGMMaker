param([Parameter(Mandatory)][string]$Command,[string]$ArgsFile)
$ErrorActionPreference='Stop'
$connection=Get-Content -LiteralPath 'C:\Users\zan12\Documents\RIGMMaker\Exchange\workspace-13184.json' -Raw | ConvertFrom-Json
$arguments=@{}
if($ArgsFile){$arguments=Get-Content -LiteralPath $ArgsFile -Raw | ConvertFrom-Json -AsHashtable}
$envelope=@{schemaVersion=1;requestId=[guid]::NewGuid().ToString();command=$Command;args=$arguments}
$bytes=[Text.Encoding]::UTF8.GetBytes(($envelope | ConvertTo-Json -Depth 32 -Compress))
if($bytes.Length -gt 60000){throw 'Payload exceeds pipe limit'}
$client=[IO.Pipes.NamedPipeClientStream]::new('.',$connection.commandPipe,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
try{
 $client.Connect(5000);$client.ReadMode=[IO.Pipes.PipeTransmissionMode]::Message
 $client.Write($bytes,0,$bytes.Length);$buffer=[byte[]]::new(65536)
 $read=$client.ReadAsync($buffer,0,$buffer.Length)
 if(-not $read.Wait(5000)){throw 'Pipe read timeout'}
 $reply=[Text.Encoding]::UTF8.GetString($buffer,0,$read.Result) | ConvertFrom-Json
 if($reply.requestId -ne $envelope.requestId -or -not $client.IsMessageComplete){throw 'Pipe response mismatch'}
 $reply | ConvertTo-Json -Depth 32
 if(-not $reply.ok){throw $reply.error.message}
}finally{$client.Dispose()}