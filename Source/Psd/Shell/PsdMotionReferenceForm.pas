unit PsdMotionReferenceForm;
interface
uses System.Classes, System.SysUtils, System.JSON, System.Types, Vcl.Forms,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Graphics, PsdCharacter, PsdWorkspace;
type
  TPsdReferenceApplyEvent = function(Sender: TObject): Boolean of object;
  TPsdMotionReferencePage = class(TPanel)
  private
    FCharacter: TPsdCharacter;
    FReference: TJSONObject; FBitmap: TBitmap;
    FCanvas: TPaintBox; FStep: TComboBox; FStatus: TLabel; FDrawRect: TRect;
    FCharacterId, FSavedReferenceText: string;
    FChanged: Boolean; FOnApply: TPsdReferenceApplyEvent; FOnReload: TNotifyEvent;
    procedure PaintReference(Sender: TObject);
    procedure ReferenceClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure Accept(Sender: TObject);
    procedure Reset(Sender: TObject);
    procedure Reload(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateForParent(AOwner: TComponent; AParent: TWinControl);
    procedure BindCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace; RefreshImage: Boolean = False);
    function TryApply: Boolean;
    procedure ShowError(const Text: string);
    destructor Destroy; override;
    property Reference: TJSONObject read FReference; // 借用。
    property HasDraft: Boolean read FChanged;
    property SavedReferenceText: string read FSavedReferenceText;
    property OnApply: TPsdReferenceApplyEvent read FOnApply write FOnApply;
    property OnReload: TNotifyEvent read FOnReload write FOnReload;
    procedure ReloadCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace);
  end;
implementation
uses System.Math, System.UITypes, Vcl.Dialogs, Winapi.Windows, PsdJson, PsdProduction, PsdAnimation;
constructor TPsdMotionReferencePage.Create(AOwner: TComponent);
begin
  if not (AOwner is TWinControl) then raise Exception.Create('Motion reference page requires a display parent');
  CreateForParent(AOwner,TWinControl(AOwner));
end;
constructor TPsdMotionReferencePage.CreateForParent(AOwner: TComponent; AParent: TWinControl);
begin
  inherited Create(AOwner); Parent := AParent; BevelOuter := bvNone; Align := alClient;
  FCharacter := TPsdCharacter.Create; // 寸法だけを所有。Sessionが文書を入れ替えても参照が失効しない。
  Font.Name := 'Yu Gothic UI'; Font.Size := 10;
  var Top := TPanel.Create(Self); Top.Parent := Self; Top.Align := alTop; Top.Height := 78; Top.BevelOuter := bvNone;
  var Guide := TLabel.Create(Self); Guide.Parent := Top; Guide.SetBounds(12,6,770,22);
  Guide.Caption := '正面画像をクリックして指定します。選択欄で指定済みの位置を修正できます。';
  FStep := TComboBox.Create(Self); FStep.Parent := Top; FStep.SetBounds(12,34,560,28); FStep.Style := csDropDownList;
  FStep.Name := 'MotionReferenceStep';
  FStep.Items.AddStrings(['1 顔の左上','2 顔の右下','3 首元','4 画面左の肩','5 画面右の肩','6 上半身下端']); FStep.ItemIndex := 0;
  var Clear := TButton.Create(Self); Clear.Parent := Top; Clear.SetBounds(588,34,180,28); Clear.Caption := '基準を指定し直す'; Clear.OnClick := Reset; Clear.Name := 'MotionReferenceReset';
  var ReadSaved := TButton.Create(Self); ReadSaved.Parent := Top; ReadSaved.SetBounds(788,34,200,28); ReadSaved.Caption := '保存済み基準を読み直す'; ReadSaved.OnClick := Reload;
  var Bottom := TPanel.Create(Self); Bottom.Parent := Self; Bottom.Align := alBottom; Bottom.Height := 80; Bottom.BevelOuter := bvNone;
  FStatus := TLabel.Create(Self); FStatus.Parent := Bottom; FStatus.SetBounds(12,6,770,40); FStatus.WordWrap := True;
  FStatus.Caption := '肩の左右は画面基準です。上半身下端は首と肩より下に指定してください。';
  var OK := TButton.Create(Self); OK.Parent := Bottom; OK.SetBounds(12,46,180,30); OK.Caption := '検証して基準を反映'; OK.OnClick := Accept;
  OK.Name := 'MotionReferenceSave';
  FCanvas := TPaintBox.Create(Self); FCanvas.Parent := Self; FCanvas.Align := alClient; FCanvas.OnPaint := PaintReference; FCanvas.OnMouseDown := ReferenceClick;
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
  if NewCharacter then begin FCharacterId := Character.Id; Reset(Self); FChanged := False; end;
  FCharacter.Document.Width := Character.Document.Width; FCharacter.Document.Height := Character.Document.Height;
  if not FChanged then begin
    FSavedReferenceText := Saved;
    if Saved<>'' then begin FReference.Free; FReference := ObjectText(Saved); end;
  end;
  if not RefreshImage and not NewCharacter then Exit;
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
  FCanvas.Invalidate;
end;
destructor TPsdMotionReferencePage.Destroy;
begin FCharacter.Free; FReference.Free; FBitmap.Free; inherited; end;
procedure TPsdMotionReferencePage.Reset(Sender: TObject);
begin
  FReference.Free;
  FReference := ObjectText('{"schemaVersion":1,"source":"manual","faceBounds":{"left":-1,"top":-1,"right":-1,"bottom":-1},"neck":{"x":-1,"y":-1},"screenLeftShoulder":{"x":-1,"y":-1},"screenRightShoulder":{"x":-1,"y":-1},"upperBodyBottomY":-1}');
  if FStep<>nil then FStep.ItemIndex := 0;
  FChanged := True;
  if (FCanvas<>nil) and HandleAllocated then FCanvas.Invalidate;
end;
procedure TPsdMotionReferencePage.PaintReference(Sender: TObject);
  function X(Value: Double): Integer;
  begin Result := FDrawRect.Left+Round(Value*FDrawRect.Width/FCharacter.Document.Width); end;
  function Y(Value: Double): Integer;
  begin Result := FDrawRect.Top+Round(Value*FDrawRect.Height/FCharacter.Document.Height); end;
  procedure Mark(const Key,LabelText: string);
  begin
    var P := Obj(FReference,Key); var PX := N(P,'x',-1); var PY := N(P,'y',-1); if (PX<0) or (PY<0) then Exit;
    FCanvas.Canvas.Ellipse(X(PX)-5,Y(PY)-5,X(PX)+5,Y(PY)+5); FCanvas.Canvas.TextOut(X(PX)+8,Y(PY),LabelText);
  end;
begin
  FCanvas.Canvas.Brush.Color := RGB(28,28,32); FCanvas.Canvas.FillRect(FCanvas.ClientRect);
  if (FBitmap=nil) or FBitmap.Empty or (FReference=nil) then Exit;
  var K := Min((FCanvas.Width-24)/FBitmap.Width,(FCanvas.Height-24)/FBitmap.Height); if K<=0 then Exit;
  var W := Round(FBitmap.Width*K); var H := Round(FBitmap.Height*K);
  FDrawRect := Rect((FCanvas.Width-W) div 2,(FCanvas.Height-H) div 2,(FCanvas.Width+W) div 2,(FCanvas.Height+H) div 2);
  FCanvas.Canvas.StretchDraw(FDrawRect,FBitmap); FCanvas.Canvas.Pen.Color := clAqua; FCanvas.Canvas.Pen.Width := 2;
  FCanvas.Canvas.Brush.Style := bsClear; FCanvas.Canvas.Font.Color := clAqua;
  var F := Obj(FReference,'faceBounds');
  if (N(F,'left',-1)>=0) and (N(F,'top',-1)>=0) and (N(F,'right',-1)>N(F,'left')) and (N(F,'bottom',-1)>N(F,'top')) then
    FCanvas.Canvas.Rectangle(X(N(F,'left')),Y(N(F,'top')),X(N(F,'right')),Y(N(F,'bottom')));
  Mark('neck','首元'); Mark('screenLeftShoulder','画面左の肩'); Mark('screenRightShoulder','画面右の肩');
  if N(FReference,'upperBodyBottomY',-1)>=0 then begin
    FCanvas.Canvas.MoveTo(FDrawRect.Left,Y(N(FReference,'upperBodyBottomY'))); FCanvas.Canvas.LineTo(FDrawRect.Right,Y(N(FReference,'upperBodyBottomY')));
    FCanvas.Canvas.TextOut(FDrawRect.Left+8,Y(N(FReference,'upperBodyBottomY'))+4,'上半身下端');
  end;
  FCanvas.Canvas.Brush.Style := bsSolid;
end;
procedure TPsdMotionReferencePage.ReferenceClick(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  if (Button<>mbLeft) or not PtInRect(FDrawRect,Point(X,Y)) or (FDrawRect.Width<1) or (FDrawRect.Height<1) then Exit;
  var PX := EnsureRange(Round((X-FDrawRect.Left)*FCharacter.Document.Width/FDrawRect.Width),0,FCharacter.Document.Width-1);
  var PY := EnsureRange(Round((Y-FDrawRect.Top)*FCharacter.Document.Height/FDrawRect.Height),0,FCharacter.Document.Height-1);
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
end;
procedure TPsdMotionReferencePage.ShowError(const Text: string);
begin FStatus.Caption := Text; end;
procedure TPsdMotionReferencePage.Reload(Sender: TObject);
begin if Assigned(FOnReload) then FOnReload(Self); end;
procedure TPsdMotionReferencePage.ReloadCharacter(Character: TPsdCharacter; Workspace: TPsdWorkspace);
begin FCharacterId := ''; FChanged := False; BindCharacter(Character,Workspace,True); end;
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
  except on E: Exception do FStatus.Caption := E.Message; end;
end;
procedure TPsdMotionReferencePage.Accept(Sender: TObject);
begin TryApply; end;
end.
