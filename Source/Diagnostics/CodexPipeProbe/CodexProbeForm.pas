unit CodexProbeForm;

// 1フォーム・入力TEdit・2送信ボタン・生成画像用TPaintBox。
// 通信はワーカー、画像の復号と描画・最終成功判定はメインスレッドが担当する。
interface

uses
  System.SysUtils, System.Classes, System.Types, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, CodexProbeTransport;

type
  TCodexProbeForm = class(TForm)
  private
    FInput: TEdit;
    FPreview: TPaintBox;
    FPicture: TPicture; // フォームが所有。元の生成画像を保持し、描画時だけ縮小する。
    FDedicated, FExisting: TButton;
    FStatus, FLogLabel, FPathLabel: TLabel;
    FTimer: TTimer;
    FWorker: TCodexProbeWorker;
    FSelfTest, FResultPath, FPromptFile, FImagePath, FDisplayError: string;
    FAutoStarted, FReceived, FImageLoaded, FImagePainted: Boolean;
    FReceivedAt: UInt64;
    FDrawRect: TRect; // 画像表示領域内の実描画範囲。
    procedure SendClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    function DrawPreview(Target: TCanvas; Width, Height: Integer): TRect;
    function DisplaySucceeded: Boolean;
    procedure SaveResult;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var CodexProbeMain: TCodexProbeForm;

implementation

uses
  System.IOUtils, System.JSON, System.Math, System.Hash, Winapi.Windows,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg;

function ArgumentValue(const Name: string): string;
begin
  Result := '';
  for var Index := 1 to ParamCount - 1 do
    if ParamStr(Index) = Name then Exit(ParamStr(Index + 1));
end;

constructor TCodexProbeForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Name := 'CodexPipeProbeForm';
  Caption := 'Codex 画像生成・パイプ受信テスト';
  Position := poScreenCenter;
  ClientWidth := 820; ClientHeight := 690;
  Constraints.MinWidth := 660; Constraints.MinHeight := 560;
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  DoubleBuffered := True;
  FPicture := TPicture.Create;
  var LabelInput := TLabel.Create(Self);
  LabelInput.Parent := Self; LabelInput.Caption := '生成したい画像'; LabelInput.SetBounds(16, 8, 300, 22);
  FInput := TEdit.Create(Self);
  FInput.Name := 'PromptEdit'; FInput.Parent := Self;
  FInput.SetBounds(16, 34, 788, 28); FInput.Anchors := [akLeft, akTop, akRight];
  FInput.Text := '青い空と海辺の小さな図書館。絵本風のイラスト。文字は入れない。';
  FInput.MaxLength := 8000;
  FDedicated := TButton.Create(Self);
  FDedicated.Name := 'DedicatedSendButton'; FDedicated.Parent := Self;
  FDedicated.SetBounds(16, 76, 240, 36); FDedicated.Caption := '専用Codexで画像生成';
  FDedicated.OnClick := SendClick;
  FExisting := TButton.Create(Self);
  FExisting.Name := 'ExistingSendButton'; FExisting.Parent := Self;
  FExisting.SetBounds(268, 76, 240, 36); FExisting.Caption := '既存Codexで画像生成';
  FExisting.OnClick := SendClick;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self; FStatus.SetBounds(16, 124, 788, 48);
  FStatus.Anchors := [akLeft, akTop, akRight]; FStatus.AutoSize := False; FStatus.WordWrap := True;
  FStatus.Caption := '送信待ち。生成画像を受信し、この画面に表示できれば成功です。';
  FPathLabel := TLabel.Create(Self);
  FPathLabel.Parent := Self; FPathLabel.SetBounds(16, 178, 788, 42);
  FPathLabel.AutoSize := False; FPathLabel.WordWrap := True; FPathLabel.Anchors := [akLeft, akTop, akRight];
  FPreview := TPaintBox.Create(Self);
  FPreview.Name := 'GeneratedImagePreview'; FPreview.Parent := Self;
  FPreview.SetBounds(16, 228, 788, 400); FPreview.Anchors := [akLeft, akTop, akRight, akBottom];
  FPreview.OnPaint := PreviewPaint;
  FLogLabel := TLabel.Create(Self);
  FLogLabel.Parent := Self; FLogLabel.SetBounds(16, 640, 788, 42);
  FLogLabel.AutoSize := False; FLogLabel.WordWrap := True; FLogLabel.Anchors := [akLeft, akRight, akBottom];
  FSelfTest := ArgumentValue('--self-test');
  FResultPath := ArgumentValue('--result'); FPromptFile := ArgumentValue('--prompt-file');
  FTimer := TTimer.Create(Self); FTimer.Interval := 100; FTimer.OnTimer := Tick;
end;

destructor TCodexProbeForm.Destroy;
begin
  FTimer.Enabled := False;
  if FWorker <> nil then begin FWorker.Terminate; FWorker.Free; end;
  FPreview.OnPaint := nil;
  FPicture.Free;
  inherited;
end;

function TCodexProbeForm.DrawPreview(Target: TCanvas; Width, Height: Integer): TRect;
var Scale: Double; DrawWidth, DrawHeight: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  Target.Brush.Color := TColor($00242424);
  Target.FillRect(Rect(0, 0, Width, Height));
  if not FImageLoaded or (FPicture.Width <= 0) or (FPicture.Height <= 0) then Exit;
  Scale := Min(Width / FPicture.Width, Height / FPicture.Height);
  DrawWidth := Max(1, Round(FPicture.Width * Scale));
  DrawHeight := Max(1, Round(FPicture.Height * Scale));
  Result := Rect((Width - DrawWidth) div 2, (Height - DrawHeight) div 2,
    (Width - DrawWidth) div 2 + DrawWidth, (Height - DrawHeight) div 2 + DrawHeight);
  Target.StretchDraw(Result, FPicture.Graphic);
end;

procedure TCodexProbeForm.PreviewPaint(Sender: TObject);
begin
  try
    FDrawRect := DrawPreview(FPreview.Canvas, FPreview.Width, FPreview.Height);
    if FImageLoaded and (FDrawRect.Width > 0) and (FDrawRect.Height > 0)
      and IsWindowVisible(Handle) then FImagePainted := True;
  except
    on E: Exception do FDisplayError := '画像の描画に失敗しました: ' + E.Message;
  end;
end;

function TCodexProbeForm.DisplaySucceeded: Boolean;
begin
  Result := (FWorker <> nil) and FWorker.Success and FImageLoaded and FImagePainted and (FDisplayError = '');
end;

procedure TCodexProbeForm.SendClick(Sender: TObject);
var Mode: TCodexProbeMode; Directory: string; Id: TGUID;
begin
  if FWorker <> nil then Exit;
  if Trim(FInput.Text) = '' then begin FStatus.Caption := '生成したい画像を入力してください。'; Exit; end;
  if Sender = FExisting then Mode := pmExisting else Mode := pmDedicated;
  CreateGUID(Id);
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'ProbeRuns\' +
    FormatDateTime('yyyymmdd-hhnnss', Now) + '-' + ProbeModeName(Mode) + '-' + GUIDToString(Id));
  try
    FWorker := TCodexProbeWorker.Create(Mode, FInput.Text, Directory);
    FReceived := False; FImageLoaded := False; FImagePainted := False;
    FImagePath := ''; FDisplayError := ''; FPathLabel.Caption := '';
    FPicture.Assign(nil); FPreview.Invalidate;
    FInput.Enabled := False; FDedicated.Enabled := False; FExisting.Enabled := False;
    FLogLabel.Caption := 'ログ：' + FWorker.LogPath;
    FWorker.BeginRun;
  except
    on E: Exception do begin
      FStatus.Caption := E.Message;
      if FSelfTest <> '' then begin ExitCode := 1; Close; end;
    end;
  end;
end;

procedure TCodexProbeForm.SaveResult;
var ResultObject: TJSONObject; Bitmap: Vcl.Graphics.TBitmap; Png: TPngImage; RenderPath: string;
begin
  if FResultPath = '' then Exit;
  ResultObject := TJSONObject.Create;
  try
    ResultObject.AddPair('mode', FSelfTest);
    ResultObject.AddPair('success', TJSONBool.Create(DisplaySucceeded));
    ResultObject.AddPair('transportSuccess', TJSONBool.Create(FWorker.Success));
    ResultObject.AddPair('answer', FWorker.Answer);
    ResultObject.AddPair('error', FWorker.ErrorText);
    ResultObject.AddPair('displayError', FDisplayError);
    ResultObject.AddPair('threadId', FWorker.ThreadId);
    ResultObject.AddPair('turnId', FWorker.TurnId);
    ResultObject.AddPair('codexExecutable', FWorker.Executable);
    ResultObject.AddPair('log', FWorker.LogPath);
    ResultObject.AddPair('inputClass', FInput.ClassName);
    ResultObject.AddPair('outputClass', FPreview.ClassName);
    ResultObject.AddPair('formCount', TJSONNumber.Create(Screen.FormCount));
    ResultObject.AddPair('startedByButtonClick', TJSONBool.Create(True));
    ResultObject.AddPair('imageGenerated', TJSONBool.Create(FWorker.ImageGenerated));
    ResultObject.AddPair('imageItemId', FWorker.ImageItemId);
    ResultObject.AddPair('sourceImagePath', FWorker.SourceImagePath);
    ResultObject.AddPair('imagePath', FImagePath);
    ResultObject.AddPair('imageLoaded', TJSONBool.Create(FImageLoaded));
    ResultObject.AddPair('imagePainted', TJSONBool.Create(FImagePainted));
    ResultObject.AddPair('imageWidth', TJSONNumber.Create(FPicture.Width));
    ResultObject.AddPair('imageHeight', TJSONNumber.Create(FPicture.Height));
    ResultObject.AddPair('windowVisible', TJSONBool.Create(IsWindowVisible(Handle)));
    ForceDirectories(ExtractFilePath(TPath.GetFullPath(FResultPath)));
    if FImageLoaded then begin
      ResultObject.AddPair('imageSha256', THashSHA2.GetHashStringFromFile(FImagePath));
      // PaintBoxと同じ描画関数の出力を、目視確認用のPNGへ保存する。
      Bitmap := Vcl.Graphics.TBitmap.Create; Png := TPngImage.Create;
      try
        Bitmap.SetSize(FPreview.Width, FPreview.Height);
        DrawPreview(Bitmap.Canvas, Bitmap.Width, Bitmap.Height);
        Png.Assign(Bitmap);
        RenderPath := ChangeFileExt(FResultPath, '.preview.png');
        Png.SaveToFile(RenderPath);
        ResultObject.AddPair('previewRender', RenderPath);
      finally Png.Free; Bitmap.Free; end;
    end;
    TFile.WriteAllText(FResultPath, ResultObject.ToJSON, TEncoding.UTF8);
  finally ResultObject.Free; end;
end;

procedure TCodexProbeForm.Tick(Sender: TObject);
begin
  if (FSelfTest <> '') and not FAutoStarted then begin
    FAutoStarted := True;
    // 自動試験でも実際のPaintBoxのPaintイベントを通すため、自分のフォームを表示する。
    ShowWindow(Handle, SW_SHOWNOACTIVATE);
    if FPromptFile <> '' then FInput.Text := TFile.ReadAllText(FPromptFile, TEncoding.UTF8).Trim;
    if FSelfTest = 'existing' then FExisting.Click
    else if FSelfTest = 'dedicated' then FDedicated.Click
    else begin FStatus.Caption := '不明なself-testモード'; ExitCode := 2; Close; end;
  end;
  if FWorker = nil then Exit;
  if not FReceived then FStatus.Caption := FWorker.Stage;
  if WaitForSingleObject(FWorker.Handle, 0) <> WAIT_OBJECT_0 then Exit;
  if not FReceived then begin
    FReceived := True; FReceivedAt := GetTickCount64;
    if FWorker.Success then begin
      try
        FImagePath := FWorker.ImagePath;
        FPicture.LoadFromFile(FImagePath);
        if (FPicture.Width <= 0) or (FPicture.Height <= 0) then raise Exception.Create('画像の寸法が不正です。');
        FImageLoaded := True;
        FPathLabel.Caption := '受信画像：' + FImagePath;
        FPreview.Repaint;
      except on E: Exception do FDisplayError := '生成画像を表示できません: ' + E.Message; end;
    end;
  end;
  if FWorker.Success and FImageLoaded and not FImagePainted and (FDisplayError = '') then begin
    if GetTickCount64 - FReceivedAt < 5000 then begin FPreview.Repaint; Exit; end;
    FDisplayError := '画像は読み込みましたが、画面上の描画を確認できませんでした。';
  end;
  if DisplaySucceeded then FStatus.Caption := Format('成功：Codexの生成画像を受信・表示しました（%d × %d）', [FPicture.Width, FPicture.Height])
  else if FDisplayError <> '' then FStatus.Caption := FDisplayError
  else FStatus.Caption := FWorker.ErrorText;
  if FSelfTest <> '' then begin
    SaveResult;
    if DisplaySucceeded then ExitCode := 0 else ExitCode := 1;
  end;
  FreeAndNil(FWorker);
  FInput.Enabled := True; FDedicated.Enabled := True; FExisting.Enabled := True;
  if FSelfTest <> '' then begin FTimer.Enabled := False; Close; end;
end;

end.
