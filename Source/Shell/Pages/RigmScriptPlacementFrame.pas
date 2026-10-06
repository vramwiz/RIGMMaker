unit RigmScriptPlacementFrame;
interface
uses System.Classes, System.JSON, System.Types, System.Generics.Collections, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ImgList,
  Winapi.Messages, RigmWizardWorkspace, RigmScriptLayoutFrame, RigmThumbnailList;
type
  TRigmPlacementPreview = class(TRigmLayoutPreview)
  private
    FGuide: Vcl.Graphics.TBitmap; FGuideKey: string; FSprites: TObjectDictionary<string,Vcl.Graphics.TBitmap>;
    FDragging: Boolean; FHandle,FRevision: Integer; FProject,FPath: string;
    FStart: TPointF; FOriginal,FWorking: TRectF; FError: string;
    FKeepAspect,FSnap: Boolean;
    procedure CancelMode(var M: TMessage); message WM_CANCELMODE;
    procedure CaptureChanged(var M: TMessage); message WM_CAPTURECHANGED;
    function ScreenRect(const R: TRectF): TRect;
    procedure Dirty(const Before,After: TRect);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure CancelDrag;
    function CharacterBounds(const Path: string): TRect;
    function HandleRect(Index: Integer): TRect;
    function ScreenToBase(X,Y: Integer): TPointF;
    property KeepAspect: Boolean read FKeepAspect write FKeepAspect;
    property SnapToGrid: Boolean read FSnap write FSnap;
    property Dragging: Boolean read FDragging;
  end;
  TRigmScriptPlacementFrame = class(TFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean; FSelectionKey: string;
    FList: TListView; FImages: TImageList; FLoader: TRigmThumbnailList;
    FFlip,FAspect,FSnap: TCheckBox; FBounds,FGuide: TLabel;
    FPreview: TRigmPlacementPreview;
    procedure Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure Flip(Sender: TObject);
    procedure Options(Sender: TObject);
    function ThumbnailPath(Item: TListItem): string;
    procedure ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    destructor Destroy; override;
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
    property Preview: TRigmPlacementPreview read FPreview;
  end;
implementation
uses System.SysUtils, System.Math, Winapi.Windows, RigmJson, RigmScriptPlacementModel,
  RigmPlacementGeometry, RigmThumbnailCache, RigmCharacterCatalog;
{$R *.dfm}
constructor TRigmPlacementPreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited CreateForWorkspace(AOwner,Workspace); Name := 'ScriptPlacementPreview'; ShowCharacters := False;
  // VCLの自動MouseUp解除より先にWM_CAPTURECHANGEDが来ると確定を失う。
  // 捕捉はこのコントロールの開始・確定・取消で一貫して管理する。
  ControlStyle := ControlStyle-[csCaptureMouse];
  FGuide := Vcl.Graphics.TBitmap.Create; FSprites := TObjectDictionary<string,Vcl.Graphics.TBitmap>.Create([doOwnsValues]);
  FKeepAspect := True; FSnap := True; ShowHint := True;
  Hint := '枠内をドラッグして移動。8点のハンドルで拡縮。スナップはFullHD基準10px。';
end;
destructor TRigmPlacementPreview.Destroy;
begin CancelDrag; FSprites.Free; FGuide.Free; inherited; end;
function TRigmPlacementPreview.ScreenRect(const R: TRectF): TRect;
begin
  var V := VideoRect;
  Result := Rect(V.Left+Round(R.Left*V.Width/1920),V.Top+Round(R.Top*V.Height/1080),
    V.Left+Round(R.Right*V.Width/1920),V.Top+Round(R.Bottom*V.Height/1080));
end;
function TRigmPlacementPreview.ScreenToBase(X,Y: Integer): TPointF;
begin var R := VideoRect; Result := PointF((X-R.Left)*1920/Max(1,R.Width),(Y-R.Top)*1080/Max(1,R.Height)); end;
function TRigmPlacementPreview.CharacterBounds(const Path: string): TRect;
begin
  Result := Rect(0,0,0,0); var O := Placement(Workspace.ScriptDraft,Path); if O=nil then Exit;
  if FDragging and SameText(Path,FPath) then Result := ScreenRect(FWorking) else Result := ScreenRect(PlacementRect(O));
end;
function TRigmPlacementPreview.HandleRect(Index: Integer): TRect;
begin Result := PlacementHandle(CharacterBounds(JS(Workspace.ScriptDraft.ScriptWizard,'placementSelected')),Index,ScaleValue(5)); end;
procedure TRigmPlacementPreview.Dirty(const Before,After: TRect);
begin
  var R: TRect; UnionRect(R,Before,After); InflateRect(R,ScaleValue(10),ScaleValue(10));
  if HandleAllocated then InvalidateRect(Handle,@R,False);
end;
procedure TRigmPlacementPreview.Paint;
begin
  var P := Workspace.ScriptDraft; if P=nil then begin inherited; Exit; end;
  var Key := P.Layout+'|'+P.LDirection+'|'+P.BackgroundColor.ToString+'|'+ClientWidth.ToString+'|'+ClientHeight.ToString+'|'+CurrentPPI.ToString;
  if (FGuideKey<>Key) or FGuide.Empty then begin
    FGuide.SetSize(Max(1,ClientWidth),Max(1,ClientHeight)); DrawGuide(FGuide.Canvas); FGuideKey := Key;
  end;
  Canvas.Draw(0,0,FGuide);
  if P.ScriptWizard.GetValue('placements')<>nil then for var V in JA(P.ScriptWizard,'placements') do begin
    var O := TJSONObject(V); var Path := JS(O,'path'); var Entry: TRigmThumbnailEntry := nil;
    try Entry := Workspace.Thumbnails.Request(Path); except end;
    if (Entry=nil) or (Length(Entry.Pixels)=0) then Continue;
    var SpriteKey := Path+'|'+Entry.Signature+'|'+BoolToStr(JB(O,'flipX'),True); var Sprite: Vcl.Graphics.TBitmap;
    if not FSprites.TryGetValue(SpriteKey,Sprite) then begin
      if FSprites.Count>=256 then FSprites.Clear;
      Sprite := Vcl.Graphics.TBitmap.Create;
      try
        Sprite.PixelFormat := pf32bit; Sprite.SetSize(Entry.Width,Entry.Height);
        for var Y := 0 to Entry.Height-1 do begin
          var D := PByte(Sprite.ScanLine[Y]);
          for var X := 0 to Entry.Width-1 do begin
            var SX := X; if JB(O,'flipX') then SX := Entry.Width-1-X;
            var N := (Y*Entry.Width+SX)*4; var A := Entry.Pixels[N+3];
            D[X*4] := Entry.Pixels[N+2]*A div 255; D[X*4+1] := Entry.Pixels[N+1]*A div 255;
            D[X*4+2] := Entry.Pixels[N]*A div 255; D[X*4+3] := A;
          end;
        end;
        Sprite.AlphaFormat := afPremultiplied; FSprites.Add(SpriteKey,Sprite);
      except Sprite.Free; raise; end;
    end;
    var R := CharacterBounds(Path); var Blend: TBlendFunction;
    Blend.BlendOp := AC_SRC_OVER; Blend.BlendFlags := 0; Blend.SourceConstantAlpha := 255; Blend.AlphaFormat := AC_SRC_ALPHA;
    Winapi.Windows.AlphaBlend(Canvas.Handle,R.Left,R.Top,R.Width,R.Height,Sprite.Canvas.Handle,0,0,Sprite.Width,Sprite.Height,Blend);
  end;
  var Selected := JS(P.ScriptWizard,'placementSelected');
  if Placement(P,Selected)<>nil then begin
    Canvas.Pen.Color := $00FFC060; Canvas.Pen.Width := ScaleValue(2); Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(CharacterBounds(Selected)); Canvas.Brush.Style := bsSolid; Canvas.Brush.Color := $00FFC060;
    for var I := 0 to 7 do Canvas.FillRect(HandleRect(I)); Canvas.Pen.Width := 1;
  end;
  if FError<>'' then begin Canvas.Font.Color := clWhite; Canvas.Brush.Style := bsClear; Canvas.TextOut(8,8,FError); Canvas.Brush.Style := bsSolid; end;
end;
procedure TRigmPlacementPreview.CancelDrag;
begin
  if not FDragging then Exit; FDragging := False; MouseCapture := False; Workspace.EndPlacementEdit; Invalidate;
end;
procedure TRigmPlacementPreview.CancelMode(var M: TMessage);
begin CancelDrag; inherited; end;
procedure TRigmPlacementPreview.CaptureChanged(var M: TMessage);
begin if FDragging and (M.LParam<>NativeInt(Handle)) then CancelDrag; inherited; end;
procedure TRigmPlacementPreview.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if (Button<>mbLeft) or (Workspace.CurrentScriptStage<>'placement') or Workspace.PlacementEditing then Exit;
  var P := Workspace.ScriptDraft; FPath := JS(P.ScriptWizard,'placementSelected'); FHandle := -1;
  if Placement(P,FPath)<>nil then for var I := 0 to 7 do if PtInRect(HandleRect(I),Point(X,Y)) then FHandle := I;
  if FHandle<0 then begin
    FPath := '';
    if P.ScriptWizard.GetValue('placements')<>nil then for var I := JA(P.ScriptWizard,'placements').Count-1 downto 0 do begin
      var O := TJSONObject(JA(P.ScriptWizard,'placements')[I]);
      if PtInRect(CharacterBounds(JS(O,'path')),Point(X,Y)) then begin FPath := JS(O,'path'); Break; end;
    end;
  end;
  if FPath='' then Exit;
  Workspace.SelectScriptPlacement(FPath); FOriginal := PlacementRect(Placement(P,FPath)); FWorking := FOriginal;
  FRevision := P.Revision; FProject := P.Id; FStart := ScreenToBase(X,Y); FError := '';
  Workspace.BeginPlacementEdit; FDragging := True; MouseCapture := True; Invalidate;
end;
procedure TRigmPlacementPreview.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited; if not FDragging then Exit;
  var Before := ScreenRect(FWorking); var P := ScreenToBase(X,Y);
  FWorking := DragPlacement(FOriginal,PlacementArea(Workspace.ScriptDraft),FHandle,P.X-FStart.X,P.Y-FStart.Y,FKeepAspect,FSnap);
  Dirty(Before,ScreenRect(FWorking));
end;
procedure TRigmPlacementPreview.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited; if (Button<>mbLeft) or not FDragging then Exit;
  MouseMove(Shift,X,Y); FDragging := False; MouseCapture := False; Workspace.EndPlacementEdit;
  if (Workspace.ScriptDraft.Id<>FProject) or (Workspace.ScriptDraft.Revision<>FRevision) then begin FError := '別の変更があったためドラッグを確定しません。'; Invalidate; Exit; end;
  var O := TJSONObject.Create;
  try
    O.AddPair('path',FPath); AddN(O,'x',FWorking.Left/1920); AddN(O,'y',FWorking.Top/1080);
    AddN(O,'width',FWorking.Width/1920); AddN(O,'height',FWorking.Height/1080);
    try Workspace.SetScriptPlacement(O); except on E: Exception do FError := E.Message; end;
  finally O.Free; Invalidate; end;
end;
constructor TRigmScriptPlacementFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace;
  FGuide := TLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alTop; FGuide.Height := 58; FGuide.AutoSize := False; FGuide.WordWrap := True;
  FGuide.Caption := '第4段階：キャラ配置　枠内で移動、8点で拡縮。L字型ではキャラ側の領域へ収めます。'+#13#10+
    '左右反転は元画像の鏡像です。Nextで配置を保存し台本入力へ進みます。最終編集でも同じ配置を調整できます。';
  var Side := TPanel.Create(Self); Side.Parent := Self; Side.Align := alLeft; Side.Width := 248; Side.Caption := ''; Side.BevelOuter := bvNone;
  FAspect := TCheckBox.Create(Self); FAspect.Parent := Side; FAspect.Align := alTop; FAspect.Height := 28; FAspect.Caption := '縦横比を保持'; FAspect.Checked := True; FAspect.OnClick := Options;
  FSnap := TCheckBox.Create(Self); FSnap.Parent := Side; FSnap.Align := alTop; FSnap.Top := 28; FSnap.Height := 28; FSnap.Caption := '10pxスナップ（FullHD基準）'; FSnap.Checked := True; FSnap.OnClick := Options;
  FFlip := TCheckBox.Create(Self); FFlip.Parent := Side; FFlip.Align := alTop; FFlip.Top := 56; FFlip.Height := 28; FFlip.Caption := '左右反転'; FFlip.Name := 'ScriptPlacementFlip'; FFlip.OnClick := Flip;
  FBounds := TLabel.Create(Self); FBounds.Name := 'ScriptPlacementBounds'; FBounds.Parent := Side; FBounds.Align := alTop; FBounds.Top := 84; FBounds.Height := 64; FBounds.AutoSize := False; FBounds.WordWrap := True;
  FImages := TImageList.Create(Self); FImages.ColorDepth := cd32Bit; FImages.Width := ScaleValue(56); FImages.Height := ScaleValue(72);
  FList := TListView.Create(Self); FList.Parent := Side; FList.Align := alClient; FList.Name := 'ScriptPlacementCharacters';
  FList.ViewStyle := vsReport; FList.ReadOnly := True; FList.RowSelect := True; FList.HideSelection := False; FList.SmallImages := FImages;
  FList.Columns.Add.Caption := 'キャラ'; FList.Columns[0].Width := 228; FList.OnSelectItem := Selected;
  FPreview := TRigmPlacementPreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Self;
  FLoader := TRigmThumbnailList.CreateForList(Self,Workspace.Thumbnails,FList,FImages);
  FLoader.OnPath := ThumbnailPath; FLoader.OnApplied := ThumbnailApplied;
end;
destructor TRigmScriptPlacementFrame.Destroy;
begin FPreview.CancelDrag; FLoader.Free; inherited; end;
function TRigmScriptPlacementFrame.ThumbnailPath(Item: TListItem): string;
begin Result := Item.SubItems[0]; end;
procedure TRigmScriptPlacementFrame.ThumbnailApplied(Sender: TObject; Item: TListItem; Metadata: TJSONObject);
begin FPreview.Invalidate; end;
procedure TRigmScriptPlacementFrame.Options(Sender: TObject);
begin FPreview.KeepAspect := FAspect.Checked; FPreview.SnapToGrid := FSnap.Checked; end;
procedure TRigmScriptPlacementFrame.Selected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FSync or not Selected or FWorkspace.PlacementEditing then Exit;
  try FWorkspace.SelectScriptPlacement(Item.SubItems[0]); except on E: Exception do FBounds.Caption := E.Message; end;
end;
procedure TRigmScriptPlacementFrame.Flip(Sender: TObject);
begin
  if FSync then Exit; var O := TJSONObject.Create;
  try O.AddPair('path',JS(FWorkspace.ScriptDraft.ScriptWizard,'placementSelected')); O.AddPair('flipX',TJSONBool.Create(FFlip.Checked));
    try FWorkspace.SetScriptPlacement(O); except on E: Exception do begin RefreshState; FBounds.Caption := E.Message; end; end;
  finally O.Free; end;
end;
procedure TRigmScriptPlacementFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit; FSync := True;
  try
    var Selected := JA(P.ScriptWizard,'selectedCharacters'); var Key := Selected.ToJSON;
    if Key<>FSelectionKey then begin
      FLoader.Reset; FList.Items.Clear; FSelectionKey := Key;
      for var V in Selected do begin var Item := FList.Items.Add; Item.Caption := '['+CharacterFormatLabel(JS(TJSONObject(V),'path'))+'] '+JS(TJSONObject(V),'name');
        Item.SubItems.Add(JS(TJSONObject(V),'path')); Item.ImageIndex := -1; end;
      FLoader.Refresh;
    end;
    var Path := JS(P.ScriptWizard,'placementSelected');
    for var Item in FList.Items do Item.Selected := SameText(Item.SubItems[0],Path);
    var O := Placement(P,Path); FFlip.Enabled := O<>nil;
    if O<>nil then begin
      FFlip.Checked := JB(O,'flipX'); var B := PlacementRect(O);
      FBounds.Caption := Format('FullHD座標  X: %.0f  Y: %.0f'+#13#10+'幅: %.0f  高さ: %.0f',[B.Left,B.Top,B.Width,B.Height]);
    end else FBounds.Caption := 'キャラ選択へ戻って選択してください。';
    FPreview.Invalidate;
  finally FSync := False; end;
end;
procedure TRigmScriptPlacementFrame.SetActive(Value: Boolean);
begin
  if Value then begin RefreshState; FLoader.Refresh; end
  else begin FPreview.CancelDrag; FLoader.Pause; end;
end;
end.
