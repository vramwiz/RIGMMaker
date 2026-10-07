// 選択中のキャラ＋感情へ適用するVOICEVOX音声設定を、6本の共通縦型スライダーで表示・編集する。
unit SerifVoicevoxAudioSettingsFrame;

interface

uses
  System.Classes, Vcl.Controls, Vcl.Forms, Vcl.Graphics, RigmBufferedControls,
  VerticalSliderControl, SerifVoicevoxAudioSettings;

type
  TFrameSerifVoicevoxAudioSettings = class(TRigmBufferedFrame)
  private const
    SLIDER_COUNT = 6;
  private
    FSliders: array[0..SLIDER_COUNT - 1] of TVerticalSliderControl;
    FOnChange: TNotifyEvent;
    FOnPreview: TNotifyEvent;
    FUpdating: Boolean;
    procedure CreateSliders;
    procedure LayoutSliders;
    procedure SliderChange(Sender: TObject);
    procedure SliderRightClick(Sender: TObject);
  protected
    procedure Resize; override;
  public
    // 6項目のスライダーを動的に生成し、AviUtl2の配色を適用する。
    constructor Create(AOwner: TComponent); override;
    function RequestFinish: Boolean;
    // 現在表示している6項目をVOICEVOX APIへ渡せるレコードとして返す。
    function GetValues: TSerifVoicevoxAudioValues;
    // 6項目を一括表示する。この復元処理ではOnChangeを通知しない。
    procedure SetValues(const Values: TSerifVoicevoxAudioValues);
    // ユーザー操作でいずれかの値が変化した時だけ通知する。
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // 現在の編集値を使った確認再生を要求する。
    property OnPreview: TNotifyEvent read FOnPreview write FOnPreview;
  end;

implementation

uses
  System.SysUtils, System.Math, AviUtl2StyleColors;

{$R *.dfm}

function TFrameSerifVoicevoxAudioSettings.RequestFinish: Boolean;
begin Result := True; for var Slider in FSliders do if not Slider.RequestFinish then Exit(False); end;

constructor TFrameSerifVoicevoxAudioSettings.Create(AOwner: TComponent);
begin
  inherited;
  Color := A2SCPanelBackground;
  Font.Color := A2SCPanelText;
  CreateSliders;
end;

procedure TFrameSerifVoicevoxAudioSettings.CreateSliders;
const
  CAPTIONS: array[0..SLIDER_COUNT - 1] of string = (
    #$901F#$5EA6, #$97F3#$9AD8, #$6291#$63DA, #$97F3#$91CF,
    #$524D#$9593, #$5F8C#$9593);
  MINIMUMS: array[0..SLIDER_COUNT - 1] of Double =
    (0.50, -0.15, 0.00, 0.00, 0.00, 0.00);
  MAXIMUMS: array[0..SLIDER_COUNT - 1] of Double =
    (2.00, 0.15, 2.00, 2.00, 5.00, 5.00);
  POSITIONS: array[0..SLIDER_COUNT - 1] of Double =
    (1.00, 0.00, 1.00, 1.00, 0.10, 0.10);
var
  I: Integer;
begin
  for I := 0 to SLIDER_COUNT - 1 do
  begin
    FSliders[I] := TVerticalSliderControl.Create(Self);
    FSliders[I].Parent := Self; FSliders[I].Name := 'VoicevoxValue'+I.ToString;
    FSliders[I].BackColor := A2SCPanelBackground;
    FSliders[I].Caption := CAPTIONS[I];
    FSliders[I].Font.Assign(Font);
    FSliders[I].Font.Size := Max(Font.Size - 2, 7);
    FSliders[I].Minimum := MINIMUMS[I];
    FSliders[I].Maximum := MAXIMUMS[I];
    FSliders[I].SmallChange := 0.01;
    FSliders[I].LargeChange := 0.10;
    FSliders[I].Decimals := 2;
    FSliders[I].Position := POSITIONS[I];
    FSliders[I].EditBackColor := A2SCEditBackground;
    FSliders[I].EditTextColor := A2SCEditText;
    FSliders[I].TextColor := A2SCPanelText;
    FSliders[I].TrackColor := $0097C981;
    FSliders[I].UpperTrackColor := $00647A68;
    FSliders[I].ThumbColor := $0097C981;
    FSliders[I].OnChange := SliderChange;
    FSliders[I].OnRightClick := SliderRightClick;
  end;
end;

function TFrameSerifVoicevoxAudioSettings.GetValues:
  TSerifVoicevoxAudioValues;
begin
  Result.SpeedScale := FSliders[0].Position;
  Result.PitchScale := FSliders[1].Position;
  Result.IntonationScale := FSliders[2].Position;
  Result.VolumeScale := FSliders[3].Position;
  Result.PrePhonemeLength := FSliders[4].Position;
  Result.PostPhonemeLength := FSliders[5].Position;
end;

procedure TFrameSerifVoicevoxAudioSettings.LayoutSliders;
var
  I: Integer;
  LeftPos: Integer;
  SliderWidth: Integer;
begin
  // ClientWidth取得前にウィンドウハンドルが必要なため、親へ接続されるまでは配置を遅延する。
  if not Assigned(Parent) or not Assigned(FSliders[0]) then Exit;
  if ClientWidth <= 0 then Exit;
  SliderWidth := Max(ClientWidth div SLIDER_COUNT, 1);
  LeftPos := 0;
  for I := 0 to SLIDER_COUNT - 1 do
  begin
    if I = SLIDER_COUNT - 1 then
      SliderWidth := ClientWidth - LeftPos;
    FSliders[I].SetBounds(LeftPos, 0, SliderWidth, ClientHeight);
    Inc(LeftPos, SliderWidth);
  end;
end;

procedure TFrameSerifVoicevoxAudioSettings.Resize;
begin
  inherited;
  LayoutSliders;
end;

procedure TFrameSerifVoicevoxAudioSettings.SetValues(
  const Values: TSerifVoicevoxAudioValues);
begin
  FUpdating := True;
  try
    FSliders[0].Position := Values.SpeedScale;
    FSliders[1].Position := Values.PitchScale;
    FSliders[2].Position := Values.IntonationScale;
    FSliders[3].Position := Values.VolumeScale;
    FSliders[4].Position := Values.PrePhonemeLength;
    FSliders[5].Position := Values.PostPhonemeLength;
  finally
    FUpdating := False;
  end;
end;

procedure TFrameSerifVoicevoxAudioSettings.SliderChange(Sender: TObject);
begin
  if not FUpdating and Assigned(FOnChange) then FOnChange(Self);
end;

procedure TFrameSerifVoicevoxAudioSettings.SliderRightClick(Sender: TObject);
begin
  if Assigned(FOnPreview) then FOnPreview(Self);
end;

end.
