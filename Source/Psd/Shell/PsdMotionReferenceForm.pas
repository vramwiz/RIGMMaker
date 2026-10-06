unit PsdMotionReferenceForm;
interface
uses System.Classes, System.SysUtils, System.JSON, System.Types, Vcl.Forms,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, PsdCharacter, PsdWorkspace,
  PsdPreviewControl, PsdSettingsPanel;
type
  TPsdReferenceApplyEvent = function(Sender: TObject): Boolean of object;
  TPsdMotionReferencePage = class(TPanel)
  private
    FCharacter: TPsdCharacter;
    FOnChanged: TNotifyEvent;
    FReference: TJSONObject; FBitmap: TBitmap;
    FImageDocument: TObject; // 比較だけに使う借用識別子。文書を参照・解放しない。
    FCanvas: TPsdPreviewControl; FSettingsPanel: TPsdSettingsPanel; FStep: TComboBox; FStatus: TLabel;
    FCharacterId, FSavedReferenceText: string;
    FChanged: Boolean; FOnApply: TPsdReferenceApplyEvent; FOnReload: TNotifyEvent;
    procedure PaintReference(Sender: TObject; Canvas: TCanvas; const ImageRect: TRect);
    procedure ReferenceClick(Sender: TObject; X,Y: Integer);
    procedure Accept(Sender: TObject);
    procedure Reset(Sender: TObject);
    procedure Reload(Sender: TObject);
  public
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    constructor Create(AOwner: TComponent); override;
    constructor CreateForParent(AOwner: TComponent; AParent: TWinControl; PreviewParent: TWinControl = nil);
    procedure BindCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace; RefreshImage: Boolean = False);
    function TryApply: Boolean;
    procedure ShowError(const Text: string);
    destructor Destroy; override;
    property Reference: TJSONObject read FReference; // 借用。
    property HasDraft: Boolean read FChanged;
    property SavedReferenceText: string read FSavedReferenceText;
    property OnApply: TPsdReferenceApplyEvent read FOnApply write FOnApply;
    property OnReload: TNotifyEvent read FOnReload write FOnReload;
    property Preview: TPsdPreviewControl read FCanvas; // 借用する左側表示面。倍率は素材の基準座標に影響しない。
    property SettingsPanel: TPsdSettingsPanel read FSettingsPanel;
    procedure ReloadCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace);
  end;
implementation
uses System.Math, System.UITypes, Vcl.Dialogs, Winapi.Windows, PsdJson, PsdProduction, PsdAnimation;
constructor TPsdMotionReferencePage.Create(AOwner: TComponent);
begin
  if not (AOwner is TWinControl) then raise Exception.Create('Motion reference page requires a display parent');
  CreateForParent(AOwner,TWinControl(AOwner));
end;
constructor TPsdMotionReferencePage.CreateForParent(AOwner: TComponent; AParent: TWinControl; PreviewParent: TWinControl);
begin
  inherited Create(AOwner); Parent := AParent; BevelOuter := bvNone; Align := alClient; DoubleBuffered := True;
  FCharacter := TPsdCharacter.Create; // 寸法だけを所有。Sessionが文書を入れ替えても参照が失効しない。
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  FSettingsPanel := TPsdSettingsPanel.Create(Self); FSettingsPanel.Parent := Self;
  if PreviewParent=nil then begin FSettingsPanel.Align := alRight; FSettingsPanel.Width := 400; end;
  FSettingsPanel.AddLabel('左の画像をクリックして基準を指定します。ホイールで拡大・縮小、ドラッグで表示を移動できます。',80);
  FStep := FSettingsPanel.AddCombo('指定する位置',nil);
  FStep.Name := 'MotionReferenceStep';
  FStep.Items.AddStrings(['1 顔の左上','2 顔の右下','3 首元','4 画面左の肩','5 画面右の肩','6 上半身下端']); FStep.ItemIndex := 0;
  FSettingsPanel.AddButton('基準を指定し直す',Reset).Name := 'MotionReferenceReset';
  FSettingsPanel.AddButton('保存済み基準を読み直す',Reload);
  FStatus := FSettingsPanel.AddLabel('',88);
  FStatus.Caption := '肩の左右は画面基準です。上半身下端は首と肩より下に指定してください。';
  FSettingsPanel.AddButton('検証して基準を反映',Accept).Name := 'MotionReferenceSave';
  FCanvas := TPsdPreviewControl.Create(Self);
  if PreviewParent=nil then FCanvas.Parent := Self else begin FCanvas.Parent := PreviewParent; FCanvas.Visible := False; end;
  FCanvas.Align := alClient; FCanvas.OnOverlay := PaintReference; FCanvas.OnImageClick := ReferenceClick;
  FCanvas.Name := 'MotionReferenceCanvas';
  Reset(Self);
  FChanged := False;
  FBitmap := Vcl.Graphics.TBitmap.Create;
end;
procedure TPsdMotionReferencePage.BindCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace; RefreshImage: Boolean);
begin
  if Character=nil then Exit;
  var Saved := ''; if Character.Settings.GetValue('motionReference') is TJSONObject then Saved := Obj(Character.Settings,'motionReference').ToJSON;
  var NewCharacter := FCharacterId<>Character.Id;
  if NewCharacter then begin FCharacterId := Character.Id; FImageDocument := nil; Reset(Self); FChanged := False; FCanvas.Fit; end;
  FCharacter.Document.Width := Character.Document.Width; FCharacter.Document.Height := Character.Document.Height;
  if not FChanged then begin
    FSavedReferenceText := Saved;
    if Saved<>'' then begin FReference.Free; FReference := ObjectText(Saved); end;
  end;
  // 操作点の情報だけを先に同期し、画像は基準ページを表示した時に作る。
  if not RefreshImage then Exit;
  if FImageDocument=Character.Document then begin FCanvas.Invalidate; Exit; end;
  if Character.Settings.GetValue('motionReference') is TJSONObject then begin
    FStatus.Caption := '保存済みの基準です。AIによる設定も確認・修正できます。';
  end;
  FBitmap.PixelFormat := pf32bit; FBitmap.SetSize(Character.Document.Width,Character.Document.Height);
  var R := TPsdRenderer.Create(Character,Workspace,0);
  try
    var State := TPsdFrameState.Default; State.Motion := 'none'; State.AutoBlink := False; var Pixels := R.Composite(State);
    for var Y := 0 to FBitmap.Height-1 do begin
      var Row := PByte(FBitmap.ScanLine[Y]);
      for var X := 0 to FBitmap.Width-1 do begin
        var P := (Y*FBitmap.Width+X)*4; var A := Pixels[P+3]; var BG := 48+((X div 24+Y div 24) mod 2)*12;
        for var C := 0 to 2 do Row[X*4+2-C] := (Pixels[P+C]*A+BG*(255-A)+127) div 255;
        Row[X*4+3] := 255;
      end;
    end;
  finally R.Free; end;
  FImageDocument := Character.Document; FCanvas.Present(FBitmap);
end;
destructor TPsdMotionReferencePage.Destroy;
begin FCanvas.Free; FCharacter.Free; FReference.Free; FBitmap.Free; inherited; end;
procedure TPsdMotionReferencePage.Reset(Sender: TObject);
begin
  FReference.Free;
  FReference := ObjectText('{"schemaVersion":1,"source":"manual","faceBounds":{"left":-1,"top":-1,"right":-1,"bottom":-1},"neck":{"x":-1,"y":-1},"screenLeftShoulder":{"x":-1,"y":-1},"screenRightShoulder":{"x":-1,"y":-1},"upperBodyBottomY":-1}');
  if FStep<>nil then FStep.ItemIndex := 0;
  FChanged := True;
  if (FCanvas<>nil) and HandleAllocated then FCanvas.Invalidate;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TPsdMotionReferencePage.PaintReference(Sender: TObject; Canvas: TCanvas; const ImageRect: TRect);
  function X(Value: Double): Integer;
  begin Result := ImageRect.Left+Round(Value*ImageRect.Width/FCharacter.Document.Width); end;
  function Y(Value: Double): Integer;
  begin Result := ImageRect.Top+Round(Value*ImageRect.Height/FCharacter.Document.Height); end;
  procedure Mark(const Key,LabelText: string);
  begin
    var P := Obj(FReference,Key); var PX := N(P,'x',-1); var PY := N(P,'y',-1); if (PX<0) or (PY<0) then Exit;
    var Radius := ScaleValue(5);
    Canvas.Ellipse(X(PX)-Radius,Y(PY)-Radius,X(PX)+Radius,Y(PY)+Radius);
    if Key='screenLeftShoulder' then
      Canvas.TextOut(X(PX)-Canvas.TextWidth(LabelText)-ScaleValue(8),Y(PY),LabelText)
    else if Key='neck' then Canvas.TextOut(X(PX)+ScaleValue(8),Y(PY)-ScaleValue(22),LabelText)
    else Canvas.TextOut(X(PX)+ScaleValue(8),Y(PY),LabelText);
  end;
begin
  if (FBitmap=nil) or FBitmap.Empty or (FReference=nil) then Exit;
  Canvas.Pen.Color := clAqua; Canvas.Pen.Width := ScaleValue(2);
  Canvas.Brush.Style := bsClear; Canvas.Font.Assign(Font); Canvas.Font.Color := clAqua;
  var F := Obj(FReference,'faceBounds');
  if (N(F,'left',-1)>=0) and (N(F,'top',-1)>=0) and (N(F,'right',-1)>N(F,'left')) and (N(F,'bottom',-1)>N(F,'top')) then
    Canvas.Rectangle(X(N(F,'left')),Y(N(F,'top')),X(N(F,'right')),Y(N(F,'bottom')));
  Mark('neck','首元'); Mark('screenLeftShoulder','画面左の肩'); Mark('screenRightShoulder','画面右の肩');
  if N(FReference,'upperBodyBottomY',-1)>=0 then begin
    Canvas.MoveTo(ImageRect.Left,Y(N(FReference,'upperBodyBottomY'))); Canvas.LineTo(ImageRect.Right,Y(N(FReference,'upperBodyBottomY')));
    Canvas.TextOut(ImageRect.Left+ScaleValue(8),Y(N(FReference,'upperBodyBottomY'))+ScaleValue(4),'上半身下端');
  end;
  Canvas.Brush.Style := bsSolid;
end;
procedure TPsdMotionReferencePage.ReferenceClick(Sender: TObject; X,Y: Integer);
begin
  var PX := EnsureRange(X,0,FCharacter.Document.Width-1); var PY := EnsureRange(Y,0,FCharacter.Document.Height-1);
  var P: TJSONObject := nil;
  case FStep.ItemIndex of
    0: begin P := Obj(FReference,'faceBounds'); Put(P,'left',TJSONNumber.Create(PX)); Put(P,'top',TJSONNumber.Create(PY)); end;
    1: begin P := Obj(FReference,'faceBounds'); Put(P,'right',TJSONNumber.Create(PX)); Put(P,'bottom',TJSONNumber.Create(PY)); end;
    2: P := Obj(FReference,'neck');
    3: P := Obj(FReference,'screenLeftShoulder');
    4: P := Obj(FReference,'screenRightShoulder');
    5: Put(FReference,'upperBodyBottomY',TJSONNumber.Create(PY));
  end;
  if (P<>nil) and (FStep.ItemIndex>=2) then begin Put(P,'x',TJSONNumber.Create(PX)); Put(P,'y',TJSONNumber.Create(PY)); end;
  Put(FReference,'source','manual'); FChanged := True; FStep.ItemIndex := Min(5,FStep.ItemIndex+1); FCanvas.Invalidate;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TPsdMotionReferencePage.ShowError(const Text: string);
begin FStatus.Caption := Text; end;
procedure TPsdMotionReferencePage.Reload(Sender: TObject);
begin if Assigned(FOnReload) then FOnReload(Self); end;
procedure TPsdMotionReferencePage.ReloadCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace);
begin FCharacterId := ''; FChanged := False; BindCharacter(Character,Workspace,True); if Assigned(FOnChanged) then FOnChanged(Self); end;
function TPsdMotionReferencePage.TryApply: Boolean;
begin
  Result := False;
  try
    ValidateMotionReference(FCharacter,FReference);
    if FChanged or (FSavedReferenceText='') then begin
      if not Assigned(FOnApply) or not FOnApply(Self) then Exit;
      FChanged := False; FSavedReferenceText := FReference.ToJSON;
    end;
    FStatus.Caption := '動き基準を確認しました。次へ進めます。'; Result := True;
    if Assigned(FOnChanged) then FOnChanged(Self);
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TPsdMotionReferencePage.Accept(Sender: TObject);
begin TryApply; end;
end.
