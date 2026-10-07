unit RigmVoicevoxUiWorker;
// 移植した詳細UIのHTTPを作品の接続先へ送る。古い選択行の要求を明示取消できる。
interface
uses System.Classes, System.Net.HttpClient;
type
  TRigmVoicevoxUiWorker = class(TThread)
  private
    FLock: TObject;
    FRequest: IHTTPRequest;
    function Cancelled: Boolean;
    procedure RequestChanged(Request: IHTTPRequest);
  protected
    procedure PrepareApi;
    procedure FinishApi;
  public
    EngineUrl: string;
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;
    procedure Cancel;
  end;
implementation
uses System.SysUtils, Winapi.ActiveX, RigmVoicevoxConfig;
constructor TRigmVoicevoxUiWorker.Create(CreateSuspended: Boolean);
begin inherited Create(CreateSuspended); FLock := TObject.Create; end;
destructor TRigmVoicevoxUiWorker.Destroy;
begin Cancel; inherited; FLock.Free; end;
function TRigmVoicevoxUiWorker.Cancelled: Boolean;
begin Result := Terminated; end;
procedure TRigmVoicevoxUiWorker.RequestChanged(Request: IHTTPRequest);
begin TMonitor.Enter(FLock); try FRequest := Request; finally TMonitor.Exit(FLock); end; end;
procedure TRigmVoicevoxUiWorker.Cancel;
var Request: IHTTPRequest;
begin
  Terminate; TMonitor.Enter(FLock); try Request := FRequest; finally TMonitor.Exit(FLock); end;
  if Request<>nil then Request.Cancel;
end;
procedure TRigmVoicevoxUiWorker.PrepareApi;
begin CoInitializeEx(nil,COINIT_MULTITHREADED); VoicevoxBaseUrl := EngineUrl; VoicevoxCancelled := Cancelled; VoicevoxRequestChanged := RequestChanged; end;
procedure TRigmVoicevoxUiWorker.FinishApi;
begin VoicevoxRequestChanged := nil; VoicevoxCancelled := nil; VoicevoxBaseUrl := ''; CoUninitialize; end;
end.
