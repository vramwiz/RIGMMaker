unit RigmVoicevoxConfig;

interface
uses System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient;

// Per-worker settings: concurrent projects cannot redirect each other's speech.
threadvar
  VoicevoxBaseUrl: string;
  VoicevoxCancelled: TFunc<Boolean>;
  VoicevoxRequestChanged: TProc<IHTTPRequest>;

function VoicevoxEndpoint(const Original: string): string;
procedure ConfigureVoicevoxClient(Client: THTTPClient);
function CheckedVoicevoxPost(Client: THTTPClient; const Url: string;
  Source: TStream; Response: TStream = nil; const Headers: TNetHeaders = nil): IHTTPResponse;
function CheckedVoicevoxGet(Client: THTTPClient; const Url: string): IHTTPResponse;

implementation

function VoicevoxEndpoint(const Original: string): string;
begin
  Result := Original;
  if VoicevoxBaseUrl <> '' then Result := VoicevoxBaseUrl+Copy(Original,Length('http://127.0.0.1:50021')+1,MaxInt);
end;
procedure ConfigureVoicevoxClient(Client: THTTPClient);
begin
  if Assigned(VoicevoxCancelled) and VoicevoxCancelled() then raise EAbort.Create('音声生成を取消しました。');
  Client.HandleRedirects := False; // Never redirect local script content to another host.
end;
function CheckedVoicevoxPost(Client: THTTPClient; const Url: string;
  Source, Response: TStream; const Headers: TNetHeaders): IHTTPResponse;
var Request: IHTTPRequest;
begin
  if Assigned(VoicevoxCancelled) and VoicevoxCancelled() then raise EAbort.Create('音声生成を取消しました。');
  Request := Client.GetRequest('POST',Url); Request.SourceStream := Source;
  if Assigned(VoicevoxRequestChanged) then VoicevoxRequestChanged(Request);
  try
    if Assigned(VoicevoxCancelled) and VoicevoxCancelled() then raise EAbort.Create('Cancelled');
    Result := Client.Execute(Request,Response,Headers);
  finally if Assigned(VoicevoxRequestChanged) then VoicevoxRequestChanged(nil); end;
  if Assigned(VoicevoxCancelled) and VoicevoxCancelled() then raise EAbort.Create('音声生成を取消しました。');
end;
function CheckedVoicevoxGet(Client: THTTPClient; const Url: string): IHTTPResponse;
var Request: IHTTPRequest;
begin
  Request := Client.GetRequest('GET',Url);
  if Assigned(VoicevoxRequestChanged) then VoicevoxRequestChanged(Request);
  try
    if Assigned(VoicevoxCancelled) and VoicevoxCancelled() then raise EAbort.Create('Cancelled');
    Result := Client.Execute(Request);
  finally if Assigned(VoicevoxRequestChanged) then VoicevoxRequestChanged(nil); end;
end;
end.
