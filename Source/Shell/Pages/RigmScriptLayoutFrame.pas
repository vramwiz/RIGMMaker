unit RigmScriptLayoutFrame;

interface
uses System.Classes, RigmScriptPageFrame, System.Types, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, RigmWizardWorkspace;
type
  TRigmLayoutPreview = class(TCustomControl)
  private
    FWorkspace: TRigmWizardWorkspace;
    FShowCharacters: Boolean;
  protected
    procedure Paint; override;
    procedure DrawGuide(Target: TCanvas);
    function VideoRect: TRect;
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    property Workspace: TRigmWizardWorkspace read FWorkspace;
    property ShowCharacters: Boolean read FShowCharacters write FShowCharacters;
  end;
  TRigmScriptLayoutFrame = class(TRigmScriptPageFrame)
  private
    FWorkspace: TRigmWizardWorkspace; FSync: Boolean;
    FChoices: TRadioGroup; FBackground: TComboBox; FGuide: TLabel;
    FPreview: TRigmLayoutPreview; FTimer: TTimer;
    procedure Changed(Sender: TObject);
    procedure Poll(Sender: TObject);
  public
    constructor CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
    procedure RefreshState;
    procedure SetActive(Value: Boolean);
  end;
implementation
uses System.SysUtils, System.JSON, System.Math, Winapi.Windows,
  RigmMovieLayout, RigmJson, RigmThumbnailCache, RigmCharacterCatalog;
const Choices: array[0..2] of string = ('theme','l-left','l-right');
  Tones: array[0..2] of string = ('dark','light','blue');
{$R *.dfm}
constructor TRigmLayoutPreview.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); FWorkspace := Workspace; DoubleBuffered := True; FShowCharacters := True;
  ControlStyle := ControlStyle+[csOpaque]; Name := 'ScriptLayoutPreview'; Align := alClient;
end;
procedure TRigmLayoutPreview.DrawGuide(Target: TCanvas);
var Base: TRect; Regions: TRigmLayoutRegions;
  function Bounds(const R: TRectF): TRect;
  begin
    Result := ScaleLayoutRect(R,Base.Width,Base.Height); OffsetRect(Result,Base.Left,Base.Top);
  end;
  procedure LabelAt(const Value: string; R: TRect; Center: Boolean = True; SingleLine: Boolean = False);
  begin
    Target.Brush.Style := bsClear; Target.Font.Color := clWhite;
    if (Value='共通背景（仮）') and (FWorkspace.ScriptDraft.BackgroundColor=LayoutBackgroundColor('light')) then Target.Font.Color := clBlack;
    Target.Font.Name := 'Yu Gothic UI'; Target.Font.Height := -Max(11,Round(25*Base.Height/1080));
    Target.TextHeight('M'); SetBkMode(Target.Handle,TRANSPARENT);
    var Flags: Cardinal := DT_WORDBREAK or DT_NOPREFIX;
    if SingleLine then Flags := DT_SINGLELINE or DT_END_ELLIPSIS or DT_NOPREFIX;
    if Center then Flags := Flags or DT_CENTER;
    DrawText(Target.Handle,PChar(Value),Length(Value),R,Flags);
    Target.Brush.Style := bsSolid;
  end;
  procedure Zone(const R: TRectF; const Caption: string; Color: TColor);
  begin
    if R.IsEmpty then Exit;
    var Box := Bounds(R); Target.Brush.Color := Color; Target.Pen.Color := $887766;
    Target.Rectangle(Box); InflateRect(Box,-5,-5); LabelAt(Caption,Box);
  end;
  procedure Characters(const R: TRectF; Side: Integer; Selected: TJSONArray; Split: Boolean);
  begin
    if R.IsEmpty then Exit;
    var Count := Selected.Count; if Split then Count := (Count+1-Side) div 2;
    if Count=0 then Exit;
    var Box := Bounds(R); Box.Top := Box.Top+Max(20,Round(48*Base.Height/1080));
    var Cols := Max(1,Ceil(Sqrt(Count*Box.Width/Max(1,Box.Height))));
    var Rows := (Count+Cols-1) div Cols; var Index := 0;
    for var I := 0 to Selected.Count-1 do begin
      if Split and ((I mod 2)<>Side) then Continue;
      var Saved := TJSONObject(Selected[I]);
      var Cell := Rect(Box.Left+Index mod Cols*Box.Width div Cols,Box.Top+Index div Cols*Box.Height div Rows,
        Box.Left+(Index mod Cols+1)*Box.Width div Cols,Box.Top+(Index div Cols+1)*Box.Height div Rows);
      Inc(Index); var Name := JS(Saved,'name'); var Entry: TRigmThumbnailEntry := nil;
      try Entry := FWorkspace.Thumbnails.Request(JS(Saved,'path')); except on E: Exception do Name := Name+'（参照不可）'; end;
      var Caption := Cell; Caption.Top := Max(Caption.Top,Caption.Bottom-Max(18,Round(35*Base.Height/1080)));
      Cell.Bottom := Caption.Top; InflateRect(Cell,-2,-2);
      if (Entry<>nil) and (Length(Entry.Pixels)>0) and (Cell.Width>12) and (Cell.Height>12) then begin
        var Bitmap := Vcl.Graphics.TBitmap.Create;
        try PaintCharacterPixels(Entry.Pixels,Entry.Width,Entry.Height,Bitmap,Cell.Width,Cell.Height);
          Target.Draw(Cell.Left,Cell.Top,Bitmap);
        finally Bitmap.Free; end;
      end else if (Entry=nil) then LabelAt('準備中',Cell) else LabelAt('画像なし',Cell);
      LabelAt(Name,Caption,True,True);
    end;
  end;
begin
  Target.Brush.Color := $1E1E1E; Target.FillRect(ClientRect);
  var Project := FWorkspace.ScriptDraft; if Project=nil then Exit;
  var W := Max(1,Min(ClientWidth,Round(ClientHeight*16/9))); var H := Max(1,Round(W*9/16));
  Base := Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2);
  Regions := MovieLayoutRegions(Project.Layout,Project.LDirection);
  Target.Brush.Color := $292929;
  if Project.Layout='theme' then Target.Brush.Color := TColor(Project.BackgroundColor);
  Target.FillRect(Base); Target.Pen.Color := $AAAAAA; Target.Brush.Style := bsClear; Target.Rectangle(Base); Target.Brush.Style := bsSolid;
  var Heading := Base; Heading.Bottom := Heading.Top+Round(80*Base.Height/1080);
  if Project.Layout='theme' then LabelAt('共通背景（仮）',Heading) else LabelAt('共通背景なし',Heading);
  Zone(Regions.Image,'説明画像（仮）',$65503C); Zone(Regions.Description,'画像の説明・補足（仮）',$43382C);
  Zone(Regions.Subtitle,'下部：字幕・セリフ（仮）',$483228);
  Zone(Regions.LeftCharacters,'画面左：キャラ領域',$3A3A3A);
  Zone(Regions.RightCharacters,'画面右：キャラ領域',$3A3A3A);
  Zone(Regions.Supplement,'キャラ側：補足説明（仮）',$4E4936);
  var Selected := JA(Project.ScriptWizard,'selectedCharacters');
  if FShowCharacters then begin
    Characters(Regions.LeftCharacters,0,Selected,Project.Layout='theme');
    Characters(Regions.RightCharacters,1,Selected,Project.Layout='theme');
  end;
end;
procedure TRigmLayoutPreview.Paint;
begin DrawGuide(Canvas); end;
function TRigmLayoutPreview.VideoRect: TRect;
begin
  var W := Max(1,Min(ClientWidth,Round(ClientHeight*16/9))); var H := Max(1,Round(W*9/16));
  Result := Rect((ClientWidth-W) div 2,(ClientHeight-H) div 2,(ClientWidth+W) div 2,(ClientHeight+H) div 2);
end;
constructor TRigmScriptLayoutFrame.CreateForWorkspace(AOwner: TComponent; Workspace: TRigmWizardWorkspace);
begin
  inherited Create(AOwner); Align := alClient; FWorkspace := Workspace; DoubleBuffered := True;
  FChoices := TRadioGroup.Create(Self); FChoices.Parent := Self; FChoices.Align := alTop; FChoices.Height := ScaleValue(78);
  FChoices.Name := 'ScriptLayoutChoices'; FChoices.Caption := '第3段階：レイアウト選択（画面基準）'; FChoices.Columns := 3;
  FChoices.Items.Add('中央型：左・右にキャラ'); FChoices.Items.Add('L字型：左にキャラ／右に画像');
  FChoices.Items.Add('逆L字型：右にキャラ／左に画像'); FChoices.OnClick := Changed;
  var BackgroundRow := TPanel.Create(Self); BackgroundRow.Parent := Self; BackgroundRow.Align := alTop;
  BackgroundRow.Height := ScaleValue(42); BackgroundRow.Top := FChoices.Height; BackgroundRow.BevelOuter := bvNone; BackgroundRow.Caption := '';
  var LabelColor := TRigmScriptLabel.Create(Self); LabelColor.Parent := BackgroundRow; LabelColor.SetBounds(ScaleValue(8),ScaleValue(11),ScaleValue(164),ScaleValue(24)); LabelColor.Caption := '中央型の共通背景色（仮）';
  FBackground := TComboBox.Create(Self); FBackground.Parent := BackgroundRow; FBackground.SetBounds(ScaleValue(260),ScaleValue(7),ScaleValue(180),ScaleValue(28));
  FBackground.Name := 'ScriptLayoutBackground'; FBackground.Style := csDropDownList;
  FBackground.Items.Add('暗色'); FBackground.Items.Add('明色'); FBackground.Items.Add('青色'); FBackground.OnChange := Changed;
  FGuide := TRigmScriptLabel.Create(Self); FGuide.Parent := Self; FGuide.Align := alTop; FGuide.Top := ScaleValue(120);
  FGuide.AutoSize := False; FGuide.Height := ScaleValue(58); FGuide.WordWrap := True; FGuide.Name := 'ScriptLayoutProgress';
  FPreview := TRigmLayoutPreview.CreateForWorkspace(Self,Workspace); FPreview.Parent := Self;
  FTimer := TTimer.Create(Self); FTimer.Enabled := False; FTimer.Interval := 100; FTimer.OnTimer := Poll;
end;
procedure TRigmScriptLayoutFrame.Changed(Sender: TObject);
begin
  if FSync or (FChoices.ItemIndex<0) or (FBackground.ItemIndex<0) then Exit;
  try FWorkspace.SetScriptLayout(Choices[FChoices.ItemIndex],Tones[FBackground.ItemIndex]);
  except on E: Exception do begin RefreshState; FGuide.Caption := E.Message; end; end;
end;
procedure TRigmScriptLayoutFrame.RefreshState;
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit;
  FSync := True;
  try
    var Choice := JS(P.ScriptWizard,'layoutChoice');
    for var I := 0 to 2 do if Choices[I]=Choice then FChoices.ItemIndex := I;
    for var I := 0 to 2 do if Tones[I]=JS(P.ScriptWizard,'backgroundTone') then FBackground.ItemIndex := I;
    FBackground.Enabled := Choice='theme';
    var State := '選択中'; if JS(P.ScriptWizard,'layoutStatus')='complete' then State := '確認済み';
    FGuide.Caption := 'レイアウト：'+State+'　／　構図見本：FullHD 1920×1080（16:9）'+#13#10+
      'キャラは選択順で仮表示しています。左の工程リストで構図と移動先を保存し、キャラ配置へ進みます。';
    FPreview.Invalidate;
  finally FSync := False; end;
end;
procedure TRigmScriptLayoutFrame.SetActive(Value: Boolean);
begin FTimer.Enabled := Value; if Value then RefreshState; end;
procedure TRigmScriptLayoutFrame.Poll(Sender: TObject);
begin
  var P := FWorkspace.ScriptDraft; if P=nil then Exit;
  var Pending := False;
  for var V in JA(P.ScriptWizard,'selectedCharacters') do
    try if FWorkspace.Thumbnails.Request(JS(TJSONObject(V),'path'))=nil then Pending := True; except end;
  FPreview.Invalidate; FTimer.Enabled := Pending;
end;
end.
