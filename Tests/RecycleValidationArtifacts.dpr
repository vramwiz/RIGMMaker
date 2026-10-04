program RecycleValidationArtifacts;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  System.Generics.Collections, System.Win.ComObj, Winapi.Windows, Winapi.ActiveX, Winapi.ShlObj, Winapi.ShellAPI;
type
  TRecycleSink = class(TInterfacedObject,IFileOperationProgressSink)
  public
    Results: TJSONArray;
    constructor Create;
    destructor Destroy; override;
    function StartOperations: HRESULT; stdcall;
    function FinishOperations(hrResult: HRESULT): HRESULT; stdcall;
    function PreRenameItem(Flags: DWORD; const Item: IShellItem; Name: LPCWSTR): HRESULT; stdcall;
    function PostRenameItem(Flags: DWORD; const Item: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; stdcall;
    function PreMoveItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR): HRESULT; stdcall;
    function PostMoveItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; stdcall;
    function PreCopyItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR): HRESULT; stdcall;
    function PostCopyItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; stdcall;
    function PreDeleteItem(Flags: DWORD; const Item: IShellItem): HRESULT; stdcall;
    function PostDeleteItem(Flags: DWORD; const Item: IShellItem; Status: HRESULT; const Created: IShellItem): HRESULT; stdcall;
    function PreNewItem(Flags: DWORD; const Destination: IShellItem; Name: LPCWSTR): HRESULT; stdcall;
    function PostNewItem(Flags: DWORD; const Destination: IShellItem; Name,Template: LPCWSTR; Attributes: DWORD; Status: HRESULT; const Created: IShellItem): HRESULT; stdcall;
    function UpdateProgress(Total,Completed: UINT): HRESULT; stdcall;
    function ResetTimer: HRESULT; stdcall;
    function PauseTimer: HRESULT; stdcall;
    function ResumeTimer: HRESULT; stdcall;
  end;
function ItemName(const Item: IShellItem): string;
begin
  Result := ''; if Item=nil then Exit;
  var P: PWideChar := nil;
  if Succeeded(Item.GetDisplayName(SIGDN_DESKTOPABSOLUTEPARSING,P)) then
    try Result := P; finally CoTaskMemFree(P); end;
end;
constructor TRecycleSink.Create;
begin inherited; Results := TJSONArray.Create; end;
destructor TRecycleSink.Destroy;
begin Results.Free; inherited; end;
function TRecycleSink.StartOperations: HRESULT; begin Result := S_OK; end;
function TRecycleSink.FinishOperations(hrResult: HRESULT): HRESULT; begin Result := S_OK; end;
function TRecycleSink.PreRenameItem(Flags: DWORD; const Item: IShellItem; Name: LPCWSTR): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PostRenameItem(Flags: DWORD; const Item: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PreMoveItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PostMoveItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PreCopyItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PostCopyItem(Flags: DWORD; const Item,Destination: IShellItem; Name: LPCWSTR; Status: HRESULT; const Created: IShellItem): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PreDeleteItem(Flags: DWORD; const Item: IShellItem): HRESULT;
begin
  // Force-recycle is set on IFileOperation. Modern Shell does not expose that
  // policy as TSF_DELETE_RECYCLE_IF_POSSIBLE (observed transfer flags: $202).
  // Keep the per-item workspace boundary check as an additional safeguard.
  var Path := ItemName(Item);
  if not Path.StartsWith('D:\DelphiProg\RIGMMaker\',True) then Result := E_ABORT else Result := S_OK;
end;
function TRecycleSink.PostDeleteItem(Flags: DWORD; const Item: IShellItem; Status: HRESULT; const Created: IShellItem): HRESULT;
begin
  var O := TJSONObject.Create; O.AddPair('sourcePath',ItemName(Item));
  O.AddPair('hresult',TJSONNumber.Create(Int64(Status))); O.AddPair('transferFlags',TJSONNumber.Create(Flags));
  O.AddPair('recycleItemReturned',TJSONBool.Create(Created<>nil)); O.AddPair('recycleLocation',ItemName(Created)); Results.AddElement(O);
  // Some Shell notifications are intermediate and have no Created item.
  // The caller must confirm the final $I metadata and $R payload before
  // accepting this operation as recoverable. Never retry with permanent delete.
  if Failed(Status) then Result := E_ABORT else Result := S_OK;
end;
function TRecycleSink.PreNewItem(Flags: DWORD; const Destination: IShellItem; Name: LPCWSTR): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.PostNewItem(Flags: DWORD; const Destination: IShellItem; Name,Template: LPCWSTR; Attributes: DWORD; Status: HRESULT; const Created: IShellItem): HRESULT; begin Result := E_ABORT; end;
function TRecycleSink.UpdateProgress(Total,Completed: UINT): HRESULT; begin Result := S_OK; end;
function TRecycleSink.ResetTimer: HRESULT; begin Result := S_OK; end;
function TRecycleSink.PauseTimer: HRESULT; begin Result := S_OK; end;
function TRecycleSink.ResumeTimer: HRESULT; begin Result := S_OK; end;
var Plan,Report: TJSONObject; Operation: IFileOperation; Sink: TRecycleSink; SinkRef: IFileOperationProgressSink;
    Item: IShellItem; Cookie: DWORD; Aborted: BOOL; HR: HRESULT;
begin
  Plan := nil; Report := TJSONObject.Create; Sink := TRecycleSink.Create; SinkRef := Sink;
  try
    try
      if ParamCount<>2 then raise Exception.Create('Arguments: explicit plan.json result.json');
      Plan := TJSONObject.ParseJSONValue(TFile.ReadAllText(ParamStr(1),TEncoding.UTF8)) as TJSONObject;
      if Plan=nil then raise Exception.Create('Invalid cleanup plan');
      if Plan.GetValue<string>('root')<>'D:\DelphiProg\RIGMMaker' then raise Exception.Create('Unexpected workspace root');
      OleCheck(CoInitializeEx(nil,COINIT_APARTMENTTHREADED));
      try
        OleCheck(CoCreateInstance(CLSID_FileOperation,nil,CLSCTX_INPROC_SERVER,IID_IFileOperation,Operation));
        OleCheck(Operation.SetOperationFlags(FOF_SILENT or FOF_NOCONFIRMATION or FOF_NOERRORUI or
          FOF_ALLOWUNDO or $00080000 {FOFX_RECYCLEONDELETE} or $00100000 {FOFX_EARLYFAILURE}));
        OleCheck(Operation.Advise(SinkRef,Cookie));
        for var V in TJSONArray(Plan.GetValue('targets')) do begin
          var Path := TPath.GetFullPath(TJSONObject(V).GetValue<string>('path'));
          if not Path.StartsWith('D:\DelphiProg\RIGMMaker\',True) or
            SameText(Path,'D:\DelphiProg\RIGMMaker\RIGMMaker.exe') or
            SameText(Path,'D:\DelphiProg\RIGMMaker\RIGMMaker.ai.exe') or
            SameText(Path,'D:\DelphiProg\RIGMMaker\RIGMMaker.workflow.exe') or
            SameText(Path,'D:\DelphiProg\RIGMMaker\RIGMMaker.preview.exe') or
            SameText(Path,'D:\DelphiProg\RIGMMaker\RIGMMaker.resume.exe') or
            Path.StartsWith('D:\DelphiProg\RIGMMaker\Win64\PreservedArtifacts\',True) or
            Path.StartsWith('D:\DelphiProg\RIGMMaker\Source\',True) or
            Path.StartsWith('D:\DelphiProg\RIGMMaker\Tests\',True) then raise Exception.Create('Protected path in cleanup plan');
          OleCheck(SHCreateItemFromParsingName(PChar(Path),nil,IID_IShellItem,Item));
          OleCheck(Operation.DeleteItem(Item,nil)); Item := nil;
        end;
        HR := Operation.PerformOperations; Operation.GetAnyOperationsAborted(Aborted);
        Report.AddPair('operationHresult',TJSONNumber.Create(Int64(HR)));
        Report.AddPair('aborted',TJSONBool.Create(Aborted));
        Report.AddPair('success',TJSONBool.Create(Succeeded(HR) and not Aborted));
        if Failed(HR) or Aborted then ExitCode := 1;
        Operation.Unadvise(Cookie); Operation := nil;
      finally CoUninitialize; end;
    except on E: Exception do begin Report.AddPair('error',E.Message); ExitCode := 1; end; end;
    Report.AddPair('method','IFileOperation RECYCLEONDELETE + ALLOWUNDO; no permanent-delete fallback; caller must verify recycle metadata and payload');
    Report.AddPair('items',Sink.Results.Clone as TJSONArray);
    TFile.WriteAllText(ParamStr(2),Report.ToJSON,TEncoding.UTF8);
  finally SinkRef := nil; Plan.Free; Report.Free; end;
end.
