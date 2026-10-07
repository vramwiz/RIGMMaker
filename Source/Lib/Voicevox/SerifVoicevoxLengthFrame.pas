// audio_queryの子音長と母音長を、発音順の共通縦型スライダーで表示・編集する。
unit SerifVoicevoxLengthFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, RigmBufferedControls,
  HorizontalScrollBarControl, VerticalSliderControl,
  SerifVoicevoxAccentView;

type
  // 1本のスライダーとaudio_query内の音素長フィールドを対応付ける表示情報。
  TSerifVoicevoxLengthSegment = record
    // スライダー下部へ表示する音素。子音だけ表記し、母音は空欄にする場合がある。
    Caption: string;
    // 更新対象を識別するconsonant_lengthまたはvowel_length。
    FieldName: string;
    // マウスを重ねた時に表示する音素種別と値の説明。
    HintText: string;
    // 古い手動編集値を再利用できるか判定する、モーラ位置と音素の識別子。
    Signature: string;
    // VOICEVOXが返した、またはユーザーが編集した音素長（秒）。
    Value: Double;
  end;

  TFrameSerifVoicevoxLength = class(TRigmBufferedFrame)
  private
    FContent: TPanel;
    FOnChange: TSerifVoicevoxAccentQueryEvent;
    FOnPreview: TNotifyEvent;
    FQueryJson: string;
    FScrollBar: THorizontalScrollBarControl;
    FSegments: TArray<TSerifVoicevoxLengthSegment>;
    FSliders: TArray<TVerticalSliderControl>;
    FUpdating: Boolean;
    FViewport: TPanel;
    function GetScrollPosition: Integer;
    procedure SetScrollPosition(Value: Integer);
    procedure ClearSliders;
    procedure CreateSlider(const Index: Integer);
    procedure LayoutSliders;
    procedure SliderChange(Sender: TObject);
    procedure ScrollPositionChange(Sender: TObject);
    procedure SliderKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure SliderRightClick(Sender: TObject);
    function UpdateQueryFromSliders: Boolean;
  protected
    procedure Resize; override;
  public
    // 横スクロール領域を生成し、子音・母音数に応じてスライダーを動的生成できるようにする。
    constructor Create(AOwner: TComponent); override;
    function RequestFinish: Boolean;
    destructor Destroy; override;
    // スライダー列を現在のモニターDPIに合わせて再配置する。
    procedure ApplyDpi;
    property ScrollPosition: Integer read GetScrollPosition write SetScrollPosition;
    // audio_queryを表示する。音素列と一致しない古い手動長さ情報は除去して返す。
    function ShowQuery(const QueryJson: string): string;
    // スライダー操作で音素長を反映したaudio_queryを通知する。
    property OnChange: TSerifVoicevoxAccentQueryEvent
      read FOnChange write FOnChange;
    // 現在の編集値を使った確認再生を要求する。
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
  end;

implementation

uses
  Winapi.Windows, System.JSON, System.Math, System.SysUtils,
  System.Generics.Collections, AviUtl2StyleColors;

{$R *.dfm}

const
  LENGTH_META_NAME = '_syncroh2_length';
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

function TryGetJsonNumber(const JsonObject: TJSONObject;
  const Name: string; out Value: Double): Boolean;
var
  JsonValue: TJSONValue;
begin
  JsonValue := JsonObject.GetValue(Name);
  Result := JsonValue is TJSONNumber;
  if Result then Value := JsonObject.GetValue<Double>(Name)
  else Value := 0;
end;

function TFrameSerifVoicevoxLength.RequestFinish: Boolean;
begin Result := True; for var Slider in FSliders do if not Slider.RequestFinish then Exit(False); end;

constructor TFrameSerifVoicevoxLength.Create(AOwner: TComponent);
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

procedure TFrameSerifVoicevoxLength.ApplyDpi;
begin
  LayoutSliders;
end;

destructor TFrameSerifVoicevoxLength.Destroy;
begin
  ClearSliders;
  inherited;
end;

procedure TFrameSerifVoicevoxLength.ClearSliders;
var
  I: Integer;
begin
  for I := 0 to High(FSliders) do FSliders[I].Free;
  SetLength(FSliders, 0);
  SetLength(FSegments, 0);
end;

procedure TFrameSerifVoicevoxLength.CreateSlider(const Index: Integer);
var
  Maximum: Double;
begin
  Maximum := Max(0.50, Ceil(FSegments[Index].Value * 10) / 10);
  FSliders[Index] := TVerticalSliderControl.Create(Self);
  FSliders[Index].Parent := FContent;
  FSliders[Index].BackColor := A2SCPanelBackground;
  FSliders[Index].Caption := FSegments[Index].Caption;
  FSliders[Index].Hint := FSegments[Index].HintText;
  FSliders[Index].ShowHint := True;
  FSliders[Index].Font.Assign(Font);
  FSliders[Index].Font.Color := A2SCPanelText;
  FSliders[Index].Minimum := 0.00;
  FSliders[Index].Maximum := Maximum;
  FSliders[Index].SmallChange := 0.01;
  FSliders[Index].LargeChange := 0.05;
  FSliders[Index].Decimals := 2;
  FSliders[Index].ShowValue := False;
  FSliders[Index].EditBackColor := A2SCEditBackground;
  FSliders[Index].EditTextColor := A2SCEditText;
  FSliders[Index].TextColor := A2SCPanelText;
  FSliders[Index].TrackColor := $0097C981;
  FSliders[Index].UpperTrackColor := $00C8C8C8;
  FSliders[Index].ThumbColor := $0097C981;
  FSliders[Index].Position := FSegments[Index].Value;
  FSliders[Index].OnChange := SliderChange;
  FSliders[Index].OnKeyDown := SliderKeyDown;
  FSliders[Index].OnRightClick := SliderRightClick;
end;

procedure TFrameSerifVoicevoxLength.LayoutSliders;
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
  FScrollBar.Height := MulDiv(SCROLL_BAR_HEIGHT, CurrentPPI, 96);
  FScrollBar.TopPadding := MulDiv(SCROLL_BAR_TOP_PADDING, CurrentPPI, 96);
  FScrollBar.SetRange(ContentWidth, FViewport.ClientWidth, SliderWidth);
  FContent.SetBounds(-FScrollBar.Position, 0, ContentWidth,
    Max(FViewport.ClientHeight, 1));
  // 音素は子音・母音・休止を別要素として並べる。モーラ列には圧縮しない。
  for I := 0 to High(FSliders) do begin
    FSliders[I].Caption := FSegments[I].Caption;
    FSliders[I].Font.Height := -MulDiv(14,CurrentPPI,96);
    FSliders[I].SetBounds(I*SliderWidth,0,SliderWidth,Min(FContent.ClientHeight,MulDiv(95,CurrentPPI,96)));
  end;
end;

function TFrameSerifVoicevoxLength.GetScrollPosition: Integer;
begin Result := FScrollBar.Position; end;
procedure TFrameSerifVoicevoxLength.SetScrollPosition(Value: Integer);
begin FScrollBar.Position := Value; end;

procedure TFrameSerifVoicevoxLength.Resize;
begin
  inherited;
  LayoutSliders;
end;

procedure TFrameSerifVoicevoxLength.ScrollPositionChange(Sender: TObject);
begin
  if Assigned(FContent) and Assigned(FScrollBar) then
    FContent.Left := -FScrollBar.Position;
end;

procedure TFrameSerifVoicevoxLength.SliderChange(Sender: TObject);
begin
  if FUpdating or not UpdateQueryFromSliders then Exit;
  if Assigned(FOnChange) then FOnChange(Self, FQueryJson);
end;

procedure TFrameSerifVoicevoxLength.SliderKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  if Key <> VK_F5 then Exit;
  Key := 0;
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

procedure TFrameSerifVoicevoxLength.SliderRightClick(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

function TFrameSerifVoicevoxLength.ShowQuery(const QueryJson: string): string;
var
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  Meta: TJSONArray;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MetaValue: TJSONValue;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  PauseValue: TJSONValue;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  SegmentIndex: Integer;
  ValidMeta: Boolean;

  procedure AddSegment(const Mora: TJSONObject; const MoraText,
    FieldName, Caption, KindName: string);
  var
    Count: Integer;
    Duration: Double;
  begin
    if not TryGetJsonNumber(Mora, FieldName, Duration) then Exit;
    Count := Length(FSegments);
    SetLength(FSegments, Count + 1);
    FSegments[Count].Caption := Caption;
    FSegments[Count].FieldName := FieldName;
    FSegments[Count].HintText := MoraText + '：' + KindName;
    FSegments[Count].Signature := MoraSignature(Mora) + #1 + FieldName;
    FSegments[Count].Value := Duration;
  end;

  procedure AddMora(const Mora: TJSONObject);
  var
    HasConsonant: Boolean;
    MoraText: string;
    Unused: Double;
  begin
    MoraText := Mora.GetValue<string>('text');
    HasConsonant := TryGetJsonNumber(Mora, 'consonant_length', Unused);
    if HasConsonant then
      AddSegment(Mora, MoraText, 'consonant_length', MoraText, '子音長');
    if HasConsonant then
      AddSegment(Mora, MoraText, 'vowel_length', '', '母音長')
    else
      AddSegment(Mora, MoraText, 'vowel_length', MoraText, '母音長');
  end;

begin
  if QueryJson=FQueryJson then Exit(FQueryJson);
  FQueryJson := QueryJson;
  FUpdating := True;
  try
    FSegments := nil;
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

      for I := 0 to AccentPhrases.Count - 1 do
      begin
        PhraseObject := AccentPhrases.Items[I] as TJSONObject;
        Moras := PhraseObject.GetValue<TJSONArray>('moras');
        for J := 0 to Moras.Count - 1 do AddMora(Moras.Items[J] as TJSONObject);
        PauseValue := PhraseObject.GetValue('pause_mora');
        if PauseValue is TJSONObject then AddMora(TJSONObject(PauseValue));
      end;

      MetaValue := RootObject.GetValue(LENGTH_META_NAME);
      if MetaValue is TJSONArray then Meta := TJSONArray(MetaValue)
      else Meta := nil;
      ValidMeta := Assigned(Meta) and
        (Meta.Count = Length(FSegments));
      if ValidMeta then
        for SegmentIndex := 0 to High(FSegments) do
        begin
          if not (Meta.Items[SegmentIndex] is TJSONObject) then
          begin
            ValidMeta := False;
            Break;
          end;
          MetaItem := TJSONObject(Meta.Items[SegmentIndex]);
          if MetaItem.GetValue<string>('signature') <>
            FSegments[SegmentIndex].Signature then
          begin
            ValidMeta := False;
            Break;
          end;
          FSegments[SegmentIndex].Value :=
            MetaItem.GetValue<Double>('length');
        end;

      if Assigned(Meta) and not ValidMeta then
      begin
        MetaPair := RootObject.RemovePair(LENGTH_META_NAME);
        MetaPair.Free;
        FQueryJson := RootObject.ToJSON;
      end;

      if Length(FSliders)<>Length(FSegments) then begin
        for var Slider in FSliders do Slider.Free;
        FSliders := nil; SetLength(FSliders,Length(FSegments));
      end;
      for SegmentIndex := 0 to High(FSegments) do
        if FSliders[SegmentIndex]=nil then CreateSlider(SegmentIndex)
        else begin
          FSliders[SegmentIndex].Hint := FSegments[SegmentIndex].HintText;
          FSliders[SegmentIndex].Maximum := Max(0.50,Ceil(FSegments[SegmentIndex].Value*10)/10);
          FSliders[SegmentIndex].Position := FSegments[SegmentIndex].Value;
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

function TFrameSerifVoicevoxLength.UpdateQueryFromSliders: Boolean;
var
  AccentPhrases: TJSONArray;
  I: Integer;
  J: Integer;
  Meta: TJSONArray;
  MetaItem: TJSONObject;
  MetaPair: TJSONPair;
  MoraObject: TJSONObject;
  Moras: TJSONArray;
  PauseValue: TJSONValue;
  PhraseObject: TJSONObject;
  RootObject: TJSONObject;
  RootValue: TJSONValue;
  SegmentIndex: Integer;

  procedure ApplySegment(const Mora: TJSONObject; const FieldName: string);
  var
    Duration: Double;
  begin
    if not Result or not TryGetJsonNumber(Mora, FieldName, Duration) then Exit;
    if SegmentIndex > High(FSegments) then
    begin
      Result := False;
      Exit;
    end;
    if FSegments[SegmentIndex].Signature <>
      MoraSignature(Mora) + #1 + FieldName then
    begin
      Result := False;
      Exit;
    end;
    SetJsonNumber(Mora, FieldName, FSliders[SegmentIndex].Position);
    MetaItem := TJSONObject.Create;
    MetaItem.AddPair('signature', FSegments[SegmentIndex].Signature);
    MetaItem.AddPair('length', TJSONNumber.Create(
      FSliders[SegmentIndex].Position));
    Meta.AddElement(MetaItem);
    Inc(SegmentIndex);
  end;

  procedure ApplyMora(const Mora: TJSONObject);
  var
    Unused: Double;
  begin
    if TryGetJsonNumber(Mora, 'consonant_length', Unused) then
      ApplySegment(Mora, 'consonant_length');
    ApplySegment(Mora, 'vowel_length');
  end;

begin
  Result := False;
  RootValue := TJSONObject.ParseJSONValue(FQueryJson);
  try
    if not (RootValue is TJSONObject) then Exit;
    RootObject := TJSONObject(RootValue);
    AccentPhrases := RootObject.GetValue<TJSONArray>('accent_phrases');

    Meta := TJSONArray.Create;
    try
      Result := True;
      SegmentIndex := 0;
      for I := 0 to AccentPhrases.Count - 1 do
      begin
        PhraseObject := AccentPhrases.Items[I] as TJSONObject;
        Moras := PhraseObject.GetValue<TJSONArray>('moras');
        for J := 0 to Moras.Count - 1 do
          ApplyMora(Moras.Items[J] as TJSONObject);
        PauseValue := PhraseObject.GetValue('pause_mora');
        if PauseValue is TJSONObject then ApplyMora(TJSONObject(PauseValue));
        if not Result then Exit;
      end;
      if SegmentIndex <> Length(FSegments) then Exit(False);
      MetaPair := RootObject.RemovePair(LENGTH_META_NAME);
      MetaPair.Free;
      RootObject.AddPair(LENGTH_META_NAME, Meta);
      Meta := nil;
      FQueryJson := RootObject.ToJSON;
    finally
      Meta.Free;
    end;
  finally
    RootValue.Free;
  end;
end;

end.
