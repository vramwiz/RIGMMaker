unit DotsProbeForm;

interface

uses System.SysUtils, System.Classes, System.JSON, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, DotsProbePipe, DotsCodexTransport;

type
  TDotsProbeForm = class(TForm)
  private
    FInput, FOutput: TMemo;
    FImageFile: TEdit;
    FStatus: TLabel;
    FPreview: TImage;
    FTimer: TTimer;
    FPipe: TProbePipe;
    FWorker: TDotsCodexJob;
    FRoot, FConnection, FPipeName, FJobId, FJobMode, FLastImage: string;
    FAccessToken: string;
    FAllowAppContainer: Boolean;
    FCancelRequested: Boolean;
    FImages, FJobs, FRequests, FResponses: TDictionary<string,string>;
    FRequestOrder: TQueue<string>;
    FCacheChars: Integer;
    function HandleRequest(const Request: string): string;
    function Perform(const Command: string; Args: TJSONObject): TJSONObject;
    function StoreImage(const Bytes: TBytes): TJSONObject;
    function ImageInfo(const Id: string; IncludeData: Boolean): TJSONObject;
    function BeginJob(Args: TJSONObject): TJSONObject;
    function JobInfo(const Id: string): TJSONObject;
    procedure Tick(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure CheckTaskbarWindow(const OutputPath: string);
  end;

var DotsProbeMain: TDotsProbeForm;

implementation

uses Winapi.Windows, System.IOUtils, System.NetEncoding, System.Hash,
  Vcl.Graphics, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

const MaxImageBytes = 4 * 1024 * 1024;

function NewId: string;
begin Result := TGUID.NewGuid.ToString.Replace('{','').Replace('}',''); end;

function TextOf(Value: TJSONObject; const Key: string): string;
begin
  Result := '';
  if (Value <> nil) and (Value.GetValue(Key) is TJSONString) then Result := Value.GetValue(Key).Value;
end;

function ArgumentValue(const Name: string): string;
begin
  Result := '';
  for var I := 1 to ParamCount-1 do if ParamStr(I) = Name then Exit(ParamStr(I+1));
end;

procedure TDotsProbeForm.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // CreateNew bypasses VCL's FCreatingMainForm initialization. Controls can
  // create our HWND before Application.CreateForm assigns MainForm, so do not
  // inherit the hidden Application window as the native owner.
  Params.WndParent := 0;
  Params.ExStyle := (Params.ExStyle or WS_EX_APPWINDOW) and not WS_EX_TOOLWINDOW;
end;

procedure TDotsProbeForm.CheckTaskbarWindow(const OutputPath: string);
var Report: TJSONObject;
  procedure Capture(const Phase: string);
  var NativeOwner: HWND; Style, ExStyle: NativeInt; Passed: Boolean;
  begin
    HandleNeeded;
    NativeOwner := GetWindow(Handle, GW_OWNER);
    Style := GetWindowLongPtr(Handle, GWL_STYLE);
    ExStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);
    Passed := (Application.MainForm = Self) and Application.MainFormOnTaskbar
      and (NativeOwner = 0) and ((Style and WS_CHILD) = 0)
      and ((ExStyle and WS_EX_APPWINDOW) <> 0) and ((ExStyle and WS_EX_TOOLWINDOW) = 0);
    Report.AddPair(Phase, TJSONObject.Create
      .AddPair('passed', TJSONBool.Create(Passed))
      .AddPair('owner', TJSONNumber.Create(Int64(NativeOwner)))
      .AddPair('style', TJSONNumber.Create(Int64(Style)))
      .AddPair('exStyle', TJSONNumber.Create(Int64(ExStyle))));
    if not Passed then raise Exception.Create('taskbar_window_check_failed: ' + Phase);
  end;
begin
  Report := TJSONObject.Create;
  try
    Report.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
    Report.AddPair('mainFormOnTaskbar', TJSONBool.Create(Application.MainFormOnTaskbar));
    try
      Capture('initial');
      RecreateWnd;
      Capture('recreated');
      Report.AddPair('passed', TJSONBool.Create(True));
    except on E: Exception do begin
      Report.AddPair('passed', TJSONBool.Create(False));
      Report.AddPair('error', E.Message);
      raise;
    end; end;
  finally
    try TFile.WriteAllText(OutputPath, Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  end;
end;

constructor TDotsProbeForm.Create(AOwner: TComponent);
var Button: TButton; Connection: TJSONObject;
begin
  inherited CreateNew(AOwner);
  Caption := 'Dots → アプリ → Codex 通信試験';
  ClientWidth := 1000; ClientHeight := 720; Position := poScreenCenter;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  for var I := 1 to ParamCount do
    if ParamStr(I)='--allow-appcontainer' then FAllowAppContainer := True;
  if FAllowAppContainer then FAccessToken := NewId.Replace('-','') + NewId.Replace('-','');
  FImages := TDictionary<string,string>.Create;
  FJobs := TDictionary<string,string>.Create;
  FRequests := TDictionary<string,string>.Create;
  FResponses := TDictionary<string,string>.Create;
  FRequestOrder := TQueue<string>.Create;
  FRoot := ArgumentValue('--state-dir');
  if FRoot = '' then FRoot := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'RIGMMaker\DotsCodexProbe\' + GetCurrentProcessId.ToString + '-' + NewId);
  FRoot := TPath.GetFullPath(FRoot);
  ForceDirectories(TPath.Combine(FRoot,'Images'));
  ForceDirectories(TPath.Combine(FRoot,'Jobs'));
  FConnection := TPath.Combine(FRoot,'connection.json');
  if FileExists(FConnection) then raise Exception.Create('接続情報が既にあります。別の --state-dir を指定してください。');
  FPipeName := 'RIGMMaker.DotsProbe.' + GetCurrentProcessId.ToString + '.' + NewId;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self;
  FStatus.SetBounds(12,8,976,65); FStatus.AutoSize := False; FStatus.WordWrap := True;
  FStatus.Caption := '接続情報: ' + FConnection;
  if FAllowAppContainer then FStatus.Caption := 'AppContainer試験モード（同一ユーザー＋接続トークン必須）' + sLineBreak + FStatus.Caption;
  FInput := TMemo.Create(Self); FInput.Parent := Self; FInput.Name := 'PromptMemo';
  FInput.SetBounds(12,80,976,110); FInput.ScrollBars := ssVertical;
  FInput.Lines.Text := '通信テストです。「こんにちは」と短く返してください。';
  for var I := 0 to 3 do begin
    Button := TButton.Create(Self); Button.Parent := Self; Button.Tag := I;
    Button.SetBounds(12 + I*244,198,232,34); Button.OnClick := ButtonClick;
    case I of
      0: Button.Caption := 'テキストをCodexへ';
      1: Button.Caption := '参照画像をCodexへ';
      2: Button.Caption := 'Codexで画像生成';
      3: Button.Caption := '実行中ジョブを中止';
    end;
  end;
  FImageFile := TEdit.Create(Self); FImageFile.Parent := Self;
  FImageFile.SetBounds(12,244,730,28);
  FImageFile.TextHint := 'PNG/JPEG/BMPの絶対パスを入力して読み込む';
  Button := TButton.Create(Self); Button.Parent := Self; Button.Tag := 4;
  Button.SetBounds(754,240,234,34); Button.Caption := '画像を読み込む'; Button.OnClick := ButtonClick;
  FOutput := TMemo.Create(Self); FOutput.Parent := Self; FOutput.Name := 'ReplyMemo';
  FOutput.SetBounds(12,286,480,420); FOutput.ReadOnly := True; FOutput.ScrollBars := ssBoth;
  FPreview := TImage.Create(Self); FPreview.Parent := Self;
  FPreview.SetBounds(504,286,484,420); FPreview.Proportional := True; FPreview.Center := True; FPreview.Stretch := True;
  FPipe := TProbePipe.Create(FPipeName, HandleRequest, FAllowAppContainer);
  Connection := TJSONObject.Create.AddPair('protocol','dots-codex-probe/1')
    .AddPair('pipeName',FPipeName).AddPair('processId',TJSONNumber.Create(GetCurrentProcessId))
    .AddPair('transport','windows-named-pipe-jsonl').AddPair('encoding','utf-8')
    .AddPair('maxFrameBytes',TJSONNumber.Create(MaxFrameBytes)).AddPair('stateDirectory',FRoot);
  if FAllowAppContainer then Connection.AddPair('accessMode','appcontainer-test')
    .AddPair('accessToken',FAccessToken).AddPair('requiresAccessToken',TJSONBool.Create(True));
  try TFile.WriteAllText(FConnection,Connection.ToJSON,TEncoding.UTF8); finally Connection.Free; end;
  FPipe.Start;
  FTimer := TTimer.Create(Self); FTimer.Interval := 100; FTimer.OnTimer := Tick;
end;

destructor TDotsProbeForm.Destroy;
begin
  if FTimer <> nil then FTimer.Enabled := False;
  FreeAndNil(FPipe);
  if FWorker <> nil then begin FWorker.Terminate; FreeAndNil(FWorker); end;
  if (FConnection <> '') and FileExists(FConnection) and (FStatus <> nil) then begin
    // Delete only discovery data belonging to this process, never another instance.
    var Value := TJSONObject.ParseJSONValue(TFile.ReadAllText(FConnection,TEncoding.UTF8));
    try if (Value is TJSONObject) and (TextOf(TJSONObject(Value),'pipeName')=FPipeName) then TFile.Delete(FConnection);
    finally Value.Free; end;
  end;
  FImages.Free; FJobs.Free; FRequests.Free; FResponses.Free; FRequestOrder.Free;
  inherited;
end;

function TDotsProbeForm.ImageInfo(const Id: string; IncludeData: Boolean): TJSONObject;
var Path: string; Picture: TPicture; Bytes: TBytes;
begin
  if not FImages.TryGetValue(Id,Path) then raise Exception.Create('unknown_image: imageIdがありません');
  if TFile.GetSize(Path)>MaxImageBytes then raise Exception.Create('image_too_large');
  Bytes := TFile.ReadAllBytes(Path); Picture := TPicture.Create;
  try
    Picture.LoadFromFile(Path);
    Result := TJSONObject.Create.AddPair('imageId',Id).AddPair('path',Path)
      .AddPair('bytes',TJSONNumber.Create(Length(Bytes)))
      .AddPair('width',TJSONNumber.Create(Picture.Width)).AddPair('height',TJSONNumber.Create(Picture.Height))
      .AddPair('sha256',LowerCase(THashSHA2.GetHashStringFromFile(Path)));
    if IncludeData then Result.AddPair('base64',TNetEncoding.Base64.EncodeBytesToString(Bytes).Replace(#13,'').Replace(#10,''));
  finally Picture.Free; end;
end;

function TDotsProbeForm.StoreImage(const Bytes: TBytes): TJSONObject;
var Extension, Id, Path: string; Picture: TPicture;
begin
  if (Length(Bytes)=0) or (Length(Bytes)>MaxImageBytes) then raise Exception.Create('image_too_large_or_empty');
  Extension := '';
  if (Length(Bytes)>=24) and (Bytes[0]=$89) and (Bytes[1]=$50) and (Bytes[2]=$4E) and (Bytes[3]=$47) then begin
    // Bound PNG allocation before invoking the VCL decoder.
    var W := (UInt64(Bytes[16]) shl 24) or (UInt64(Bytes[17]) shl 16) or (UInt64(Bytes[18]) shl 8) or Bytes[19];
    var H := (UInt64(Bytes[20]) shl 24) or (UInt64(Bytes[21]) shl 16) or (UInt64(Bytes[22]) shl 8) or Bytes[23];
    if (W=0) or (H=0) or (W>8192) or (H>8192) or (W*H>16777216) then raise Exception.Create('invalid_image_dimensions');
    Extension := '.png';
  end else if (Length(Bytes)>=3) and (Bytes[0]=$FF) and (Bytes[1]=$D8) and (Bytes[2]=$FF) then Extension := '.jpg'
  else if (Length(Bytes)>=2) and (Bytes[0]=$42) and (Bytes[1]=$4D) then Extension := '.bmp';
  if Extension='' then raise Exception.Create('unsupported_image: PNG/JPEG/BMPのみ');
  Id := NewId; Path := TPath.Combine(FRoot,'Images\'+Id+Extension);
  Picture := TPicture.Create;
  try
    TFile.WriteAllBytes(Path,Bytes);
    try
      Picture.LoadFromFile(Path);
      if (Picture.Width<=0) or (Picture.Height<=0) or (Picture.Width>8192) or (Picture.Height>8192)
        or (Int64(Picture.Width)*Picture.Height>16777216) then raise Exception.Create('invalid_image_dimensions');
      FPreview.Picture.Assign(Picture);
      FImages.Add(Id,Path); FLastImage := Id;
    except TFile.Delete(Path); raise; end;
  finally Picture.Free; end;
  Result := ImageInfo(Id,False);
end;

function TDotsProbeForm.BeginJob(Args: TJSONObject): TJSONObject;
var Prompt, Mode, ImageId, Path: string; References: TArray<string>;
begin
  if FWorker<>nil then raise Exception.Create('busy: 実行中です');
  if FJobs.Count>=128 then raise Exception.Create('job_limit: アプリを再起動してください');
  Prompt := TextOf(Args,'text'); Mode := TextOf(Args,'mode'); ImageId := TextOf(Args,'imageId');
  if (Prompt.Trim='') or (Length(Prompt)>32000) then raise Exception.Create('invalid_text: 1～32000文字');
  if (Mode<>'text') and (Mode<>'image') then raise Exception.Create('invalid_mode: text/image');
  if ImageId<>'' then begin
    if not FImages.TryGetValue(ImageId,Path) then raise Exception.Create('unknown_image');
    References := TArray<string>.Create(Path);
  end;
  FJobId := NewId; FJobMode := Mode; FCancelRequested := False;
  Path := TPath.Combine(FRoot,'Jobs\'+FJobId);
  if Mode='image' then FWorker := TDotsCodexJob.CreateImage(Prompt,References,Path)
  else begin FWorker := TDotsCodexJob.Create(Prompt,nil,Path); FWorker.SetReferences(References); end;
  FInput.Lines.Text := Prompt;
  FJobs.Add(FJobId,''); FWorker.BeginRun;
  Result := JobInfo(FJobId);
end;

function TDotsProbeForm.JobInfo(const Id: string): TJSONObject;
var Saved: string;
begin
  if not FJobs.TryGetValue(Id,Saved) then raise Exception.Create('unknown_job');
  if Saved<>'' then Exit(TJSONObject.ParseJSONValue(Saved) as TJSONObject);
  Result := TJSONObject.Create.AddPair('jobId',Id).AddPair('mode',FJobMode)
    .AddPair('state','running').AddPair('stage',FWorker.Stage).AddPair('logPath',FWorker.LogPath);
end;

procedure TDotsProbeForm.Tick(Sender: TObject);
var Result, ImageResult: TJSONObject; State, ErrorText: string;
begin
  if FWorker=nil then Exit;
  FStatus.Caption := FWorker.Stage + sLineBreak + '接続情報: ' + FConnection;
  if WaitForSingleObject(FWorker.Handle,0)<>WAIT_OBJECT_0 then Exit;
  State := 'failed'; ErrorText := FWorker.ErrorText;
  if FCancelRequested then State := 'cancelled'
  else if FWorker.Success then State := 'completed';
  Result := TJSONObject.Create.AddPair('jobId',FJobId).AddPair('mode',FJobMode)
    .AddPair('state',State).AddPair('text',FWorker.Answer).AddPair('logPath',FWorker.LogPath);
  try
    if (State='completed') and (FJobMode='image') then begin
      try
        if TFile.GetSize(FWorker.ImagePath)>MaxImageBytes then raise Exception.Create('image_too_large: 試験の画像上限は4MiB');
        ImageResult := StoreImage(TFile.ReadAllBytes(FWorker.ImagePath));
        Result.AddPair('image',ImageResult);
      except on E: Exception do begin
        State := 'failed'; ErrorText := E.Message;
        Result.RemovePair('state').Free; Result.AddPair('state',State);
      end; end;
    end;
    if State<>'completed' then Result.AddPair('error',ErrorText);
    FJobs[FJobId] := Result.ToJSON;
    TFile.WriteAllText(TPath.Combine(FRoot,'Jobs\'+FJobId+'\result.json'),Result.ToJSON,TEncoding.UTF8);
    FOutput.Lines.Text := Result.Format;
    FStatus.Caption := State + sLineBreak + '接続情報: ' + FConnection;
  finally Result.Free; FreeAndNil(FWorker); end;
end;

function TDotsProbeForm.Perform(const Command: string; Args: TJSONObject): TJSONObject;
begin
  if Command='ping' then Exit(TJSONObject.Create.AddPair('protocol','dots-codex-probe/1').AddPair('message','pong'));
  if Command='status' then Exit(TJSONObject.Create.AddPair('stateDirectory',FRoot)
    .AddPair('busy',TJSONBool.Create(FWorker<>nil)).AddPair('lastImageId',FLastImage));
  if Command='echo' then begin
    if not (Args.GetValue('text') is TJSONString) then raise Exception.Create('invalid_text');
    FOutput.Lines.Text := TextOf(Args,'text');
    Exit(TJSONObject.Create.AddPair('text',TextOf(Args,'text')));
  end;
  if Command='text.save' then begin
    if not (Args.GetValue('text') is TJSONString) then raise Exception.Create('invalid_text');
    var Id := NewId; var Path := TPath.Combine(FRoot,Id+'.txt');
    TFile.WriteAllText(Path,TextOf(Args,'text'),TEncoding.UTF8);
    Exit(TJSONObject.Create.AddPair('path',Path));
  end;
  if Command='codex.start' then Exit(BeginJob(Args));
  if Command='job.get' then begin Tick(nil); Exit(JobInfo(TextOf(Args,'jobId'))); end;
  if Command='job.cancel' then begin
    var Id := TextOf(Args,'jobId');
    if (FWorker<>nil) and (FJobId=Id) then begin FCancelRequested := True; FWorker.Terminate; end;
    Exit(JobInfo(Id));
  end;
  if Command='image.put' then begin
    var Data := TextOf(Args,'base64');
    if (Data='') or (Length(Data)>((MaxImageBytes+2) div 3)*4) then raise Exception.Create('invalid_image_data');
    Exit(StoreImage(TNetEncoding.Base64.DecodeStringToBytes(Data)));
  end;
  if Command='image.get' then Exit(ImageInfo(TextOf(Args,'imageId'),True));
  raise Exception.Create('unknown_command: ' + Command);
end;

function TDotsProbeForm.HandleRequest(const Request: string): string;
var Parsed: TJSONValue; Value, Reply, Data, Args: TJSONObject;
  Id, Command, Canonical, Previous: string;
begin
  Id := ''; Command := ''; Canonical := ''; Parsed := TJSONObject.ParseJSONValue(Request);
  Reply := nil;
  try
    try
      if not (Parsed is TJSONObject) then raise Exception.Create('invalid_json: object required');
      Value := TJSONObject(Parsed); Id := TextOf(Value,'id'); Command := TextOf(Value,'command');
      if FAllowAppContainer and (TextOf(Value,'accessToken')<>FAccessToken) then
        raise Exception.Create('unauthorized: connection.jsonのaccessTokenを指定してください');
      if (Id='') or (Length(Id)>128) then raise Exception.Create('invalid_id');
      if not (Value.GetValue('version') is TJSONNumber) or (Value.GetValue('version').Value<>'1') then
        raise Exception.Create('invalid_version');
      if not (Value.GetValue('args') is TJSONObject) then raise Exception.Create('invalid_args: object required');
      // Credentials are checked before replay and never copied into the log/cache.
      Value.RemovePair('accessToken').Free;
      Canonical := THashSHA2.GetHashString(Value.ToJSON);
      if FRequests.TryGetValue(Id,Previous) then begin
        if Previous<>Canonical then raise Exception.Create('id_conflict');
        Exit(FResponses[Id]);
      end;
      Args := TJSONObject(Value.GetValue('args'));
      Data := Perform(Command,Args);
      Reply := TJSONObject.Create.AddPair('version',TJSONNumber.Create(1)).AddPair('id',Id)
        .AddPair('ok',TJSONBool.Create(True)).AddPair('data',Data);
    except on E: Exception do begin
      Reply := TJSONObject.Create.AddPair('version',TJSONNumber.Create(1)).AddPair('id',Id)
        .AddPair('ok',TJSONBool.Create(False)).AddPair('error',TJSONObject.Create
          .AddPair('code',E.Message.Split([':',' '])[0]).AddPair('message',E.Message));
    end; end;
    Result := Reply.ToJSON;
    // Poll requests use a NEW id each time. Bound cached results to 256 / 16M chars.
    if (Id<>'') and (Canonical<>'') and not FRequests.ContainsKey(Id) then begin
      while (FRequestOrder.Count>0) and ((FRequestOrder.Count>=256)
        or (FCacheChars+Length(Result)>16*1024*1024)) do begin
        var Expired := FRequestOrder.Dequeue;
        Dec(FCacheChars,Length(FResponses[Expired])); FRequests.Remove(Expired); FResponses.Remove(Expired);
      end;
      FRequests.Add(Id,Canonical); FResponses.Add(Id,Result); FRequestOrder.Enqueue(Id);
      Inc(FCacheChars,Length(Result));
    end;
    TFile.AppendAllText(TPath.Combine(FRoot,'pipe.log'),FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz',Now)
      + ' id=' + Id + ' command=' + Command + ' ok=' + Reply.GetValue('ok').Value + sLineBreak,TEncoding.UTF8);
  finally Parsed.Free; Reply.Free; end;
end;

procedure TDotsProbeForm.ButtonClick(Sender: TObject);
var Args, Result: TJSONObject; Kind: NativeInt;
begin
  Args := TJSONObject.Create; Result := nil;
  try
    try
      Kind := TButton(Sender).Tag;
      if Kind=4 then begin
        var Path := Trim(FImageFile.Text);
        if not FileExists(Path) or (TFile.GetSize(Path)>MaxImageBytes) then raise Exception.Create('画像のパスと4MiB上限を確認してください。');
        Result := StoreImage(TFile.ReadAllBytes(Path));
      end else if Kind=3 then begin
        Args.AddPair('jobId',FJobId); Result := Perform('job.cancel',Args);
      end else begin
        Args.AddPair('text',FInput.Text);
        if Kind=2 then Args.AddPair('mode','image') else Args.AddPair('mode','text');
        if Kind=1 then begin
          if FLastImage='' then raise Exception.Create('先に画像を読み込んでください。');
          Args.AddPair('imageId',FLastImage);
        end;
        Result := BeginJob(Args);
      end;
      FOutput.Lines.Text := Result.Format;
    except on E: Exception do FOutput.Lines.Text := E.Message; end;
  finally Result.Free; Args.Free; end;
end;

end.
