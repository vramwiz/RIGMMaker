// audio_queryの各モーラのpitchを、横並びの共通縦型スライダーで表示・編集する。
unit SerifVoicevoxIntonationFrame;

interface

uses
  System.Classes, System.Types, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, RigmBufferedControls,
  HorizontalScrollBarControl, VerticalSliderControl,
  SerifVoicevoxAccentView;

type
  TFrameSerifVoicevoxIntonation = class(TRigmBufferedFrame)
  private
    FContent: TPanel;
    FOnChange: TSerifVoicevoxAccentQueryEvent;
    FOnPreview: TNotifyEvent;
    FQueryJson: string;
    FScrollBar: THorizontalScrollBarControl;
    FSliders: TArray<TVerticalSliderControl>;
    FUpdating: Boolean;
    FViewport: TPanel;
    FCells: TArray<TRect>; FSharedWidth: Integer; FSharedLayout: Boolean;
    FOnScrollChange: TNotifyEvent;
    function GetScrollPosition: Integer;
    procedure SetScrollPosition(Value: Integer);
    procedure ClearSliders;
    procedure CreateSlider(const Index: Integer; const MoraText: string;
      const Pitch: Double);
    procedure LayoutSliders;
    procedure SliderKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure SliderRightClick(Sender: TObject);
    procedure SliderChange(Sender: TObject);
    procedure ScrollPositionChange(Sender: TObject);
    function UpdateQueryFromSliders: Boolean;
  protected
    procedure Resize; override;
  public
    // 横スクロール領域を生成し、モーラ数に応じてスライダーを動的生成できるようにする。
    constructor Create(AOwner: TComponent); override;
    function RequestFinish: Boolean;
    destructor Destroy; override;
    // スライダー列を現在のモニターDPIに合わせて再配置する。
    procedure ApplyDpi;
    procedure SetMoraLayout(const Cells: TArray<TRect>; ContentWidth: Integer);
    property ScrollPosition: Integer read GetScrollPosition write SetScrollPosition;
    property OnScrollChange: TNotifyEvent read FOnScrollChange write FOnScrollChange;
    // audio_queryを表示する。KeepDisplayでは空の更新待ち中だけ既存スライダーを操作不可で保持する。
    function ShowQuery(const QueryJson: string;
      const KeepDisplay: Boolean = False): string;
    // スライダー操作でpitchを反映したaudio_queryを通知する。
    property OnChange: TSerifVoicevoxAccentQueryEvent
      read FOnChange write FOnChange;
    // 現在の編集値を使った確認再生を要求する。
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
  end;

implementation

uses
  Winapi.Windows, System.JSON, System.Math, System.SysUtils,
  System.Generics.Collections,
  AviUtl2StyleColors;

{$R *.dfm}

const
  INTONATION_META_NAME = '_syncroh2_intonation';
  SCROLL_BAR_HEIGHT = 26;
  SCROLL_BAR_TOP_PADDING = 14;
  SCROLL_BAR_TRACK_COLOR = $002C4A66;
  SCROLL_BAR_THUMB_COLOR = $004691DA;
  SLIDER_WIDTH = 32;

procedure SetJsonNumber(JsonObject: TJSONObject; const Name: string;
  const Value: Double);
var
  Pair: TJSONPair;
begin
  Pair := JsonObject.RemovePair(Name);
  Pair.Free;
  JsonObject.AddPair(Name, TJSONNumber.Create(Value));
end;

function MoraSignature(const MoraObject: TJSONObject): string;
var
  Value: TJSONValue;
begin
  Result := MoraObject.GetValue<string>('text');
  Value := MoraObject.GetValue('consonant');
  if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
  Value := MoraObject.GetValue('vowel');
  if Assigned(Value) then Result := Result + #1 + Value.ToJSON;
end;

function TFrameSerifVoicevoxIntonation.RequestFinish: Boolean;
begin Result := True; for var Slider in FSliders do if not Slider.RequestFinish then Exit(False); end;

constructor TFrameSerifVoicevoxIntonation.Create(AOwner: TComponent);
begin
  inherited;
  Color := A2SCPanelBackground;
  DoubleBuffered := True;

  FScrollBar := THorizontalScrollBarControl.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Align := alBottom;
  FScrollBar.Height := SCROLL_BAR_HEIGHT;
  FScrollBar.TopPadding := SCROLL_BAR_TOP_PADDING;
  FScrollBar.BackgroundColor := A2SCPanelBackground;
  FScrollBar.TrackColor := SCROLL_BAR_TRACK_COLOR;
  FScrollBar.ThumbColor := SCROLL_BAR_THUMB_COLOR;
  FScrollBar.OnChange := ScrollPositionChange;

  FViewport := TPanel.Create(Self);
  FViewport.Parent := Self;
  FViewport.Align := alClient;
  FViewport.BevelOuter := bvNone;
  FViewport.Color := A2SCPanelBackground;
  FViewport.ParentBackground := False; FViewport.DoubleBuffered := True;

  FContent := TPanel.Create(Self);
  FContent.Parent := FViewport;
  FContent.BevelOuter := bvNone;
  FContent.Color := A2SCPanelBackground;
  FContent.ParentBackground := False; FContent.DoubleBuffered := True;
end;

procedure TFrameSerifVoicevoxIntonation.ApplyDpi;
begin
  LayoutSliders;
end;

destructor TFrameSerifVoicevoxIntonation.Destroy;
begin
  ClearSliders;
  inherited;
end;

procedure TFrameSerifVoicevoxIntonation.ClearSliders;
var
  I: Integer;
begin
  for I := 0 to High(FSliders) do FSliders[I].Free;
  SetLength(FSliders, 0);
end;

procedure TFrameSerifVoicevoxIntonation.CreateSlider(const Index: Integer;
  const MoraText: string; const Pitch: Double);
begin
  FSliders[Index] := TVerticalSliderControl.Create(Self);
  FSliders[Index].Parent := FContent;
  FSliders[Index].BackColor := A2SCPanelBackground;
  FSliders[Index].Caption := MoraText;
  FSliders[Index].Font.Assign(Font);
  FSliders[Index].Font.Color := A2SCPanelText;
  FSliders[Index].Minimum := Min(0.00, Floor(Pitch));
  FSliders[Index].Maximum := Max(7.00, Ceil(Pitch));
  FSliders[Index].SmallChange := 0.01;
  FSliders[Index].LargeChange := 0.10;
  FSliders[Index].Decimals := 2;
  FSliders[Index].ShowValue := False;
  FSliders[Index].EditBackColor := A2SCEditBackground;
  FSliders[Index].EditTextColor := A2SCEditText;
  FSliders[Index].TextColor := A2SCPanelText;
  FSliders[Index].TrackColor := $0097C981;
  FSliders[Index].UpperTrackColor := $00C8C8C8;
  FSliders[Index].ThumbColor := $0097C981;
  FSliders[Index].Position := Pitch;
  FSliders[Index].OnChange := SliderChange;
  FSliders[Index].OnKeyDown := SliderKeyDown;
  FSliders[Index].OnRightClick := SliderRightClick;
end;

procedure TFrameSerifVoicevoxIntonation.LayoutSliders;
var
  ContentWidth: Integer;
  I: Integer;
  SliderWidth: Integer;
begin
  if not Assigned(FContent) or not Assigned(FViewport) or
    not Assigned(FScrollBar) then Exit;
  SliderWidth := MulDiv(SLIDER_WIDTH, CurrentPPI, 96);
  ContentWidth := Max(Length(FSliders) * SliderWidth,
    FViewport.ClientWidth);
  if FSharedLayout then ContentWidth := Max(FSharedWidth,FViewport.ClientWidth);
  FScrollBar.Height := MulDiv(SCROLL_BAR_HEIGHT, CurrentPPI, 96);
  FScrollBar.TopPadding := MulDiv(SCROLL_BAR_TOP_PADDING, CurrentPPI, 96);
  FScrollBar.SetRange(ContentWidth, FViewport.ClientWidth, SliderWidth);
  FContent.SetBounds(-FScrollBar.Position, 0, ContentWidth,
    Max(FViewport.ClientHeight, 1));
  for I := 0 to High(FSliders) do
    if FSharedLayout and (I<Length(FCells)) then
      FSliders[I].SetBounds(FCells[I].Left,0,FCells[I].Width,MulDiv(95,CurrentPPI,96))
    else FSliders[I].SetBounds(I * SliderWidth, 0, SliderWidth,FContent.ClientHeight);
end;

procedure TFrameSerifVoicevoxIntonation.SetMoraLayout(const Cells: TArray<TRect>; ContentWidth: Integer);
begin FSharedLayout := True; FCells := Copy(Cells); FSharedWidth := ContentWidth; LayoutSliders; end;
function TFrameSerifVoicevoxIntonation.GetScrollPosition: Integer;
begin Result := FScrollBar.Position; end;
procedure TFrameSerifVoicevoxIntonation.SetScrollPosition(Value: Integer);
begin FScrollBar.Position := Value; end;

procedure TFrameSerifVoicevoxIntonation.Resize;
begin
  inherited;
  LayoutSliders;
end;

procedure TFrameSerifVoicevoxIntonation.ScrollPositionChange(Sender: TObject);
begin
  if Assigned(FContent) and Assigned(FScrollBar) then
    FContent.Left := -FScrollBar.Position;
  if Assigned(FOnScrollChange) then FOnScrollChange(Self);
end;

procedure TFrameSerifVoicevoxIntonation.SliderChange(Sender: TObject);
begin
  if FUpdating or not UpdateQueryFromSliders then Exit;
  if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
end;

procedure TFrameSerifVoicevoxIntonation.SliderKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_F5 then Exit;
  Key := 0;
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

procedure TFrameSerifVoicevoxIntonation.SliderRightClick(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

function TFrameSerifVoicevoxIntonation.ShowQuery(
  const QueryJson: string; const KeepDisplay: Boolean): string;
var
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  Meta: TJSONArray;
  MetaValue: TJSONValue;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MoraCount: Integer;
  MoraIndex: Integer;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  MoraText: string;
  PhraseObject: TJSONObject;
  Pitch: Double;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  ValidMeta: Boolean;
begin
  if (QueryJson=FQueryJson) and not KeepDisplay then Exit(FQueryJson);
  FQueryJson := QueryJson;
  if KeepDisplay and (Trim(FQueryJson) = '') then
  begin
    for I := 0 to High(FSliders) do FSliders[I].Enabled := False;
    Exit(FQueryJson);
  end;
  FUpdating := True;
  try
    RootValue := TJSONObject.ParseJSONValue(FQueryJson);
    try
      if not (RootValue is TJSONObject) then
      begin
        FQueryJson := '';
        ClearSliders;
        Exit(FQueryJson);
      end;
      RootObject := TJSONObject(RootValue);
      AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
      if not Assigned(AccentPhrases) then
      begin
        FQueryJson := '';
        ClearSliders;
        Exit(FQueryJson);
      end;

      MoraCount := 0;
      for I := 0 to AccentPhrases.Count - 1 do
      begin
        PhraseObject := AccentPhrases.Items[I] as TJSONObject;
        Moras := PhraseObject.GetValue<TJSONArray>('moras');
        if Assigned(Moras) then Inc(MoraCount, Moras.Count);
      end;

      MetaValue := RootObject.GetValue(INTONATION_META_NAME);
      if MetaValue is TJSONArray then Meta := TJSONArray(MetaValue)
      else Meta := nil;
      ValidMeta := Assigned(Meta) and (Meta.Count = MoraCount);
      MoraIndex := 0;
      if ValidMeta then
        for I := 0 to AccentPhrases.Count - 1 do
        begin
          PhraseObject := AccentPhrases.Items[I] as TJSONObject;
          Moras := PhraseObject.GetValue<TJSONArray>('moras');
          if not Assigned(Moras) then Continue;
          for J := 0 to Moras.Count - 1 do
          begin
            MoraObject := Moras.Items[J] as TJSONObject;
            if not (Meta.Items[MoraIndex] is TJSONObject) then
            begin
              ValidMeta := False;
              Break;
            end;
            MetaItem := TJSONObject(Meta.Items[MoraIndex]);
            if MetaItem.GetValue<string>('signature') <>
              MoraSignature(MoraObject) then
            begin
              ValidMeta := False;
              Break;
            end;
            Inc(MoraIndex);
          end;
          if not ValidMeta then Break;
        end;

      if Assigned(Meta) and not ValidMeta then
      begin
        MetaPair := RootObject.RemovePair(INTONATION_META_NAME);
        MetaPair.Free;
        FQueryJson := RootObject.ToJSON;
        Meta := nil;
      end;

      if Length(FSliders)<>MoraCount then begin ClearSliders; SetLength(FSliders,MoraCount); end;
      MoraIndex := 0;
      for I := 0 to AccentPhrases.Count - 1 do
      begin
        PhraseObject := AccentPhrases.Items[I] as TJSONObject;
        Moras := PhraseObject.GetValue<TJSONArray>('moras');
        if not Assigned(Moras) then Continue;
        for J := 0 to Moras.Count - 1 do
        begin
          MoraObject := Moras.Items[J] as TJSONObject;
          MoraText := MoraObject.GetValue<string>('text');
          Pitch := MoraObject.GetValue<Double>('pitch');
          if ValidMeta then
            Pitch := TJSONObject(Meta.Items[MoraIndex]).GetValue<Double>(
              'pitch');
          if FSliders[MoraIndex]=nil then CreateSlider(MoraIndex,MoraText,Pitch)
          else begin
            FSliders[MoraIndex].Caption := MoraText;
            FSliders[MoraIndex].Minimum := Min(0.00,Floor(Pitch));
            FSliders[MoraIndex].Maximum := Max(7.00,Ceil(Pitch));
            FSliders[MoraIndex].Position := Pitch;
          end;
          FSliders[MoraIndex].Enabled := True;
          Inc(MoraIndex);
        end;
      end;
    finally
      RootValue.Free;
    end;
    LayoutSliders;
  finally
    FUpdating := False;
  end;
  Result := FQueryJson;
end;

function TFrameSerifVoicevoxIntonation.UpdateQueryFromSliders: Boolean;
var
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  Meta: TJSONArray;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MoraIndex: Integer;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
begin
  Result := False;
  RootValue := TJSONObject.ParseJSONValue(FQueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');
    if not Assigned(AccentPhrases) then Exit;

    Meta := TJSONArray.Create;
    try
      MoraIndex := 0;
      for I := 0 to AccentPhrases.Count - 1 do
      begin
        PhraseObject := AccentPhrases.Items[I] as TJSONObject;
        Moras := PhraseObject.GetValue<TJSONArray>('moras');
        if not Assigned(Moras) then Continue;
        for J := 0 to Moras.Count - 1 do
        begin
          if MoraIndex > High(FSliders) then Exit;
          MoraObject := Moras.Items[J] as TJSONObject;
          SetJsonNumber(MoraObject, 'pitch', FSliders[MoraIndex].Position);
          MetaItem := TJSONObject.Create;
          MetaItem.AddPair('text', MoraObject.GetValue<string>('text'));
          MetaItem.AddPair('signature', MoraSignature(MoraObject));
          MetaItem.AddPair('pitch', TJSONNumber.Create(
            FSliders[MoraIndex].Position));
          Meta.AddElement(MetaItem);
          Inc(MoraIndex);
        end;
      end;
      if MoraIndex <> Length(FSliders) then Exit;
      MetaPair := RootObject.RemovePair(INTONATION_META_NAME);
      MetaPair.Free;
      RootObject.AddPair(INTONATION_META_NAME, Meta);
      Meta := nil;
      FQueryJson := RootObject.ToJSON;
      Result := True;
    finally
      Meta.Free;
    end;
  finally
    RootValue.Free;
  end;
end;

end.
