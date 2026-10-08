program EffectsGuiProbe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.JSON,
  System.Math, System.Hash, Winapi.Windows, Winapi.Messages,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardWorkspace, RigmScriptVoiceEffectsFrame, RigmMovieModel,
  RigmMovieComposition, RigmScriptTextModel, RigmScriptReviewModel,
  RigmScriptCastingModel, RigmScriptVoiceModel, RigmMovieLayout,
  RigmVoiceEffects, RigmVoiceEffectSettings, RigmVoiceEffectPresets, RigmAul2EffectDefinition,
  RigmAul2VolumeControl, RigmAul2LampSwitch, VoicevoxToolbarButtons,
  RigmJson, PsdJson, RigmMovieAudio, RigmAudioFilePaths, RigmVoiceEffectsPreview;
{$R *.res}
function OwnedPrintWindow(Window: HWND; DC: HDC; Flags: UINT): BOOL; stdcall;
  external 'user32.dll' name 'PrintWindow';
type
  TControlAccess = class(TControl);
  TProbeHost = class
  public
    Form: TForm;
    Workspace: TRigmWizardWorkspace;
    Frame: TRigmScriptVoiceEffectsFrame;
    Stage: TScrollBox;
    Canvas: TPanel;
    procedure Changed(Sender: TObject);
    procedure Layout;
    procedure Resize(Sender: TObject);
    procedure GuiException(Sender: TObject; E: Exception);
  end;
var
  Host: TProbeHost;
  Checks, Bounds: TJSONArray;
  OutputRoot, FixtureRoot, SavedPath, Cue0, Cue1, Source0, Source1: string;
  SourceHash0, SourceHash1, ManuscriptHash: string;
  UnhandledError: string;

procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then raise Exception.Create(Name);
  Checks.Add(Name); Writeln('PASS ',Name);
end;

procedure Pump(Milliseconds: Cardinal);
begin
  var Deadline := GetTickCount64+Milliseconds;
  repeat
    Application.ProcessMessages;
    if UnhandledError<>'' then raise Exception.Create(UnhandledError);
    Sleep(5);
  until GetTickCount64>=Deadline;
end;

procedure WaitFor(const Name: string; const Condition: TFunc<Boolean>; Milliseconds: Cardinal=6000);
begin
  var Deadline := GetTickCount64+Milliseconds;
  repeat
    Application.ProcessMessages;
    if UnhandledError<>'' then raise Exception.Create(UnhandledError);
    if Condition() then begin Check(True,Name); Exit; end;
    Sleep(10);
  until GetTickCount64>=Deadline;
  var Notice := Host.Frame.FindComponent('ScriptEffectsStatus') as TLabel;
  if Notice<>nil then Writeln('Status: ',Notice.Caption);
  Check(False,Name+' timed out');
end;

procedure TProbeHost.Changed(Sender: TObject);
begin if Frame<>nil then Frame.RefreshState; end;

procedure TProbeHost.Layout;
begin
  if (Stage=nil) or (Canvas=nil) then Exit;
  Canvas.SetBounds(0,0,Max(MulDiv(800,Form.CurrentPPI,96),Stage.ClientWidth),
    Max(MulDiv(520,Form.CurrentPPI,96),Stage.ClientHeight));
end;

procedure TProbeHost.Resize(Sender: TObject);
begin Layout; end;

procedure TProbeHost.GuiException(Sender: TObject; E: Exception);
begin UnhandledError := 'GUI '+E.ClassName+': '+E.Message; Writeln('FAIL ',UnhandledError); end;

procedure WriteWave(const Path: string; Frequency: Double);
const Rate=24000; Count=36000;
var Samples: TArray<SmallInt>; S: TFileStream;
  procedure Four(const Value: AnsiString); begin S.WriteBuffer(Value[1],4); end;
  procedure U32(Value: Cardinal); begin S.WriteBuffer(Value,4); end;
  procedure U16(Value: Word); begin S.WriteBuffer(Value,2); end;
begin
  ForceDirectories(AudioFilePath(ExtractFileDir(Path))); SetLength(Samples,Count);
  for var I := 0 to Count-1 do begin
    var Envelope := Min(1.0,Min(I/(Rate*0.04),(Count-1-I)/(Rate*0.04)));
    // Low level synthetic PCM is test-owned; no synthesis engine is invoked.
    Samples[I] := Round(2400*Envelope*Sin(2*Pi*Frequency*I/Rate));
  end;
  S := TFileStream.Create(AudioFilePath(Path),fmCreate);
  try
    Four('RIFF'); U32(36+Count*2); Four('WAVE'); Four('fmt '); U32(16);
    U16(1); U16(1); U32(Rate); U32(Rate*2); U16(2); U16(16);
    Four('data'); U32(Count*2); S.WriteBuffer(Samples[0],Count*2);
  finally S.Free; end;
end;

procedure PrepareFixture;
begin
  Host.Workspace.StartPipe(FixtureRoot); Host.Workspace.NewScriptDraft;
  var P := Host.Workspace.ScriptDraft;
  P.Speaker('narrator').StyleId := 0;
  P.Speaker('narrator').VoiceUuid := 'owned-fixture-voice';
  PrepareScriptText(P);
  var BodyText := 'Owned audio fixture one.'+#13#10+'Owned audio fixture two.';
  PsdJson.Put(ScriptSection(P,'body'),'text',BodyText);
  var Scene := TRigmMovieScene.Create; Scene.Title := 'Owned fixture'; P.Scenes.Add(Scene);
  for var I := 0 to 1 do begin
    var C := TRigmMovieCue.Create; C.Scene := Scene.Id; C.Pause := 0;
    if I=0 then begin C.Text := 'Owned audio fixture one.'; Cue0 := C.Id; end
    else begin C.Text := 'Owned audio fixture two.'; Cue1 := C.Id; end;
    C.Subtitle := C.Text; P.Cues.Add(C);
  end;
  var Cast := TJSONObject.Create; PsdJson.Put(P.ScriptWizard,'casting',Cast);
  Cast.AddPair('format','RIGMMaker.ScriptCasting'); AddN(Cast,'schemaVersion',1);
  Cast.AddPair('state','ready'); Cast.AddPair('requestId','owned-test'); Cast.AddPair('selectedCue',Cue0);
  var Roles := TJSONArray.Create; Cast.AddPair('roles',Roles);
  var Role := TJSONObject.Create; Roles.AddElement(Role);
  AddN(Role,'number',1); Role.AddPair('path','RIGM\owned-fixture.rigm');
  Role.AddPair('speakerId','narrator'); AddB(Role,'active',True);
  var Rows := TJSONArray.Create; Cast.AddPair('rows',Rows); var Offset := 0;
  for var C in P.Cues do begin
    var Row := TJSONObject.Create; Rows.AddElement(Row); Row.AddPair('cueId',C.Id);
    Row.AddPair('section','body'); AddN(Row,'offset',Offset); AddN(Row,'length',Length(C.Text));
    AddN(Row,'role',1); Row.AddPair('origin','human'); AddB(Row,'confirmed',True);
    Inc(Offset,Length(C.Text)+2);
  end;
  Cast.AddPair('sourceFingerprint',ScriptFingerprint(P));
  Cast.AddPair('fingerprint',CastingFingerprint(P));
  P.Layout := 'theme'; P.LDirection := 'right'; P.BackgroundColor := LayoutBackgroundColor('dark');
  PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'layoutStatus','complete');
  PsdJson.Put(P.ScriptWizard,'backgroundTone','dark');
  PsdJson.Put(P.ScriptWizard,'titleInput','Owned voice effects probe');
  PsdJson.Put(P.ScriptWizard,'titleStatus','complete');
  PsdJson.Put(P.ScriptWizard,'castingStatus','complete');
  PsdJson.Put(P.ScriptWizard,'stage','voice-effects');
  PsdJson.Put(P.ScriptWizard,'furthestStage','voice-effects');
  PsdJson.Put(P.ScriptWizard,'voiceStatus','complete');
  PsdJson.Put(P.ScriptWizard,'voice-effectsStatus','in-progress');
  PrepareScriptVoiceEffects(P);
  SavedPath := P.FileName;
  Source0 := TPath.Combine(ExtractFileDir(SavedPath),'Audio\'+#$65E5+#$672C+#$8A9E+' fixture 1.wav');
  Source1 := TPath.Combine(ExtractFileDir(SavedPath),'Audio\'+#$65E5+#$672C+#$8A9E+' fixture 2.wav');
  WriteWave(Source0,220); WriteWave(Source1,330);
  for var C in P.Cues do begin
    if C.Id=Cue0 then C.WaveFile := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(P.FileName)),Source0)
    else C.WaveFile := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(P.FileName)),Source1);
    C.AudioSeconds := 1.5; C.AudioKey := P.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  end;
  P.Changed; Host.Workspace.SaveScriptDraft;
  Host.Workspace.OpenScriptDraft(SavedPath);
  Check(Host.Workspace.CurrentScriptStage='voice-effects','fixture resumes at voice-effects');
  P := Host.Workspace.ScriptDraft;
  Check(P.AudioReady(P.Cue(Cue0)) and P.AudioReady(P.Cue(Cue1)),'both owned Unicode PCM cues are ready');
  SourceHash0 := THashSHA2.GetHashStringFromFile(Source0); SourceHash1 := THashSHA2.GetHashStringFromFile(Source1);
  ManuscriptHash := ScriptFingerprint(P);
end;

function Button(const Name: string): TVoicevoxToolbarButton;
begin
  Result := Host.Frame.FindComponent(Name) as TVoicevoxToolbarButton;
  Check(Result<>nil,'toolbar exists '+Name);
end;

function Enabled(Control: TControl): Boolean;
begin Result := TControlAccess(Control).Enabled; end;

function StopEnabled: Boolean;
begin Result := Enabled(Host.Frame.FindComponent('ScriptEffectsStop') as TControl); end;

function PlayOpened(Loop: Boolean): Boolean;
begin
  var Name := 'ScriptEffectsPlay'; if Loop then Name := 'ScriptEffectsLoop';
  Result := (Host.Frame.FindComponent(Name) as TVoicevoxToolbarButton).Selected;
end;

function MeasuredCurrent: Boolean;
begin
  var Caption := (Host.Frame.FindComponent('ScriptEffectsMeasurements') as TLabel).Caption;
  Result := (Pos('RMS',Caption)>0) and (Pos('前回',Caption)=0);
end;

function PreviewReady(const CueId: string): Boolean;
begin
  var P := Host.Workspace.ScriptDraft; var C := P.Cue(CueId);
  Result := (C.EffectAudioKey=CueEffectPreviewKey(P,C)) and
    (C.EffectWaveFile<>'') and FileExists(ResolveMoviePath(P.FileName,C.EffectWaveFile));
end;

procedure SelectRow(Index: Integer);
begin
  var List := Host.Frame.FindComponent('ScriptVoiceEffectsRows') as TListView;
  Check((Index>=0) and (Index<List.Items.Count),'row available '+Index.ToString);
  List.Items[Index].Selected := True; List.Items[Index].Focused := True;
  Pump(200);
  Check(JS(JO(Host.Workspace.ScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue')=
    Host.Workspace.ScriptDraft.Cues[Index].Id,'row selection reaches stable cue ID');
end;

procedure SelectEffect(Index: Integer);
begin
  var List := Host.Frame.FindComponent('ScriptEffectKind') as TListBox;
  List.ItemIndex := Index; List.OnClick(List); Pump(20);
end;

function VolumeEdit(Volume: TAul2VolumeControl): TEdit;
begin
  Result := nil;
  for var I := 0 to Volume.ControlCount-1 do if Volume.Controls[I] is TEdit then
    Exit(TEdit(Volume.Controls[I]));
end;

procedure SetGain(Value: Double);
begin
  var Volume := Host.Frame.FindComponent('ScriptEffectValue0') as TAul2VolumeControl;
  var Edit := VolumeEdit(Volume); Check(Edit<>nil,'gain has native edit');
  Edit.Text := FloatToStr(Value,TFormatSettings.Invariant);
  Check(Volume.CommitPendingValue,'native knob commits gain'); Pump(20);
end;

procedure ReachAndMeasure(Control: TControl; const CaseName: string);
begin
  var Parent := Control.Parent;
  while Parent<>nil do begin
    if Parent is TScrollBox then TScrollBox(Parent).ScrollInView(Control);
    Parent := Parent.Parent;
  end;
  Pump(10);
  var Pos := Host.Stage.ScreenToClient(Control.ClientToScreen(Point(0,0)));
  var O := TJSONObject.Create; Bounds.AddElement(O);
  O.AddPair('case',CaseName); O.AddPair('control',Control.Name); O.AddPair('class',Control.ClassName);
  AddN(O,'x',Pos.X); AddN(O,'y',Pos.Y); AddN(O,'width',Control.Width); AddN(O,'height',Control.Height);
  AddN(O,'viewportWidth',Host.Stage.ClientWidth); AddN(O,'viewportHeight',Host.Stage.ClientHeight);
  AddN(O,'ppi',Control.CurrentPPI);
  Check(TWinControl(Control).Showing and (Pos.X>=0) and (Pos.Y>=0) and
    (Pos.X+Control.Width<=Host.Stage.ClientWidth+1) and
    (Pos.Y+Control.Height<=Host.Stage.ClientHeight+1),CaseName+' reachable '+Control.Name);
end;

procedure Capture(const Name: string);
  function HasRenderedPixels(Bitmap: TBitmap): Boolean;
  begin
    Result := False;
    for var Y := 0 to 19 do for var X := 0 to 19 do
      if ColorToRGB(Bitmap.Canvas.Pixels[X*(Bitmap.Width-1) div 19,Y*(Bitmap.Height-1) div 19])<>ColorToRGB(clFuchsia) then Exit(True);
  end;
begin
  Host.Stage.HorzScrollBar.Position := 0; Host.Stage.VertScrollBar.Position := 0;
  Pump(30); Host.Form.Update;
    var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try
      var R: TRect; GetWindowRect(Host.Form.Handle,R);
      Bitmap.SetSize(R.Width,R.Height); Bitmap.PixelFormat := pf24bit;
      Bitmap.Canvas.Brush.Color := clFuchsia;
      Bitmap.Canvas.FillRect(Rect(0,0,Bitmap.Width,Bitmap.Height));
      var Printed := OwnedPrintWindow(Host.Form.Handle,Bitmap.Canvas.Handle,0);
      if not Printed or not HasRenderedPixels(Bitmap) then begin
        Writeln('CAPTURE PrintWindow unavailable; visible=',IsWindowVisible(Host.Form.Handle),
          ' size=',R.Width,'x',R.Height,' lastError=',GetLastError);
        Bitmap.Free; Bitmap := TBitmap.Create; Bitmap.PixelFormat := pf24bit;
        Bitmap.SetSize(Host.Form.ClientWidth,Host.Form.ClientHeight);
        Bitmap.Canvas.Brush.Color := clFuchsia;
        Bitmap.Canvas.FillRect(Rect(0,0,Bitmap.Width,Bitmap.Height));
        Host.Form.PaintTo(Bitmap.Canvas,0,0);
        Writeln('CAPTURE VCL PaintTo owned client ',Name);
      end else Writeln('CAPTURE PrintWindow flags0 ',Name);
      Check((Bitmap.Width>0) and (Bitmap.Height>0),'owned render size '+Name);
      if not HasRenderedPixels(Bitmap) then Writeln('CAPTURE WARNING no rendered pixels ',Name);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(OutputRoot,Name+'.png'));
      Bitmap.Free; Bitmap := TBitmap.Create; Bitmap.PixelFormat := pf24bit;
      Bitmap.SetSize(Host.Frame.Width,Host.Frame.Height);
      Bitmap.Canvas.Brush.Color := clFuchsia;
      Bitmap.Canvas.FillRect(Rect(0,0,Bitmap.Width,Bitmap.Height));
      // Render the existing native frame state. This is an owned VCL client render,
      // not a desktop screenshot; outer canvas/background differences are documented.
      Host.Frame.PaintTo(Bitmap.Canvas,0,0);
      Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(OutputRoot,Name+'-frame.png'));
  finally Png.Free; Bitmap.Free; end;
end;

procedure CheckLabelText(LabelControl: TLabel; const CaseName: string);
begin
  if not LabelControl.Visible or (LabelControl.Caption='') then Exit;
  var Bitmap := TBitmap.Create;
  try
    Bitmap.Canvas.Font.Assign(LabelControl.Font);
    var R := Rect(0,0,LabelControl.Width,0); var Flags := DT_CALCRECT or DT_EXPANDTABS;
    if LabelControl.WordWrap then Flags := Flags or DT_WORDBREAK;
    DrawText(Bitmap.Canvas.Handle,PChar(LabelControl.Caption),-1,R,Flags);
    Check(R.Height<=LabelControl.Height,CaseName+' label text fits '+LabelControl.Name);
  finally Bitmap.Free; end;
end;

procedure CheckLayout;
begin
  var BeforeText := ScriptFingerprint(Host.Workspace.ScriptDraft);
  for var PPI in [96,144,192,144,96] do begin
    Host.Form.Scaled := True; Host.Form.ScaleForPPI(PPI); Host.Form.Scaled := False;
    for var Size in [0,1] do begin
      if Size=0 then begin Host.Form.ClientWidth := 1400; Host.Form.ClientHeight := 900; end
      else begin Host.Form.ClientWidth := 1024; Host.Form.ClientHeight := 650; end;
      Host.Form.Realign; Host.Layout; Pump(100);
      var CaseName := PPI.ToString+'ppi-size'+Size.ToString;
      Check(Host.Frame.CurrentPPI=PPI,CaseName+' frame has requested PPI');
      for var Name in ['ScriptEffectsPlay','ScriptEffectsLoop','ScriptEffectsStop','ScriptEffectPreset','ScriptEffectApplyPreset','ScriptEffectOn'] do
        ReachAndMeasure(Host.Frame.FindComponent(Name) as TControl,CaseName);
      for var EffectIndex := 0 to CONTROLLER_EFFECT_COUNT-1 do begin
        SelectEffect(EffectIndex); var Definition: TControllerEffectDefinition;
        GetControllerEffectDefinition(EffectIndex,Definition);
        for var Name in ['ScriptEffectDescription','ScriptEffectModeLabel','ScriptEffectGraphLabel','ScriptEffectsMeasurements','ScriptEffectsStatus'] do
          CheckLabelText(Host.Frame.FindComponent(Name) as TLabel,CaseName+'/effect'+EffectIndex.ToString);
        for var I := 0 to High(Definition.Volumes) do begin
          var Volume := Host.Frame.FindComponent('ScriptEffectValue'+I.ToString) as TAul2VolumeControl;
          ReachAndMeasure(Volume,CaseName+'/effect'+EffectIndex.ToString);
          var Edit := VolumeEdit(Volume); Check(Edit<>nil,CaseName+' knob edit exists');
          var Bitmap := TBitmap.Create;
          try Bitmap.Canvas.Font.Assign(Edit.Font);
            Check(Bitmap.Canvas.TextHeight('0123456789')<=Edit.ClientHeight,
              CaseName+' knob numeric text fits '+EffectIndex.ToString+'/'+I.ToString);
            Bitmap.Canvas.Font.Assign(Volume.Font); Bitmap.Canvas.Font.Style := [fsBold];
              var CaptionHeight := Bitmap.Canvas.TextHeight(Volume.DisplayName);
              var CaptionBox := MulDiv(18,Volume.CurrentPPI,96);
              Writeln('FONT ',CaseName,' effect=',EffectIndex,' knob=',I,' fontPPI=',Volume.Font.PixelsPerInch,
                ' fontHeight=',Volume.Font.Height,' caption=',CaptionHeight,' box=',CaptionBox);
              Check(CaptionHeight<=CaptionBox,CaseName+' knob caption text fits '+EffectIndex.ToString+'/'+I.ToString);
          finally Bitmap.Free; end;
          Check(Edit.Font.PixelsPerInch=Edit.CurrentPPI,CaseName+' knob edit font PPI '+EffectIndex.ToString+'/'+I.ToString);
        end;
      end;
      SelectEffect(0);
      Capture('effects-'+CaseName);
    end;
  end;
  Check(ScriptFingerprint(Host.Workspace.ScriptDraft)=BeforeText,'DPI/layout exploration preserves manuscript');
end;

procedure CheckPresets;
  procedure Adopt(Index: Integer);
  begin
    var Combo := Host.Frame.FindComponent('ScriptEffectPreset') as TComboBox;
    var Apply := Host.Frame.FindComponent('ScriptEffectApplyPreset') as TButton;
    Combo.ItemIndex := Index;
    // 実ボタンのクリック経路を通す。コンボの選択自体には副作用がない。
    Apply.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(8,8));
    Apply.Perform(WM_LBUTTONUP,0,MakeLParam(8,8)); Pump(30);
  end;
  procedure CheckRowColor(Index: Integer; Active: Boolean; const CaseName: string);
  begin
    var List := Host.Frame.FindComponent('ScriptEffectKind') as TListBox;
    List.TopIndex := Index; List.Update; Pump(10);
    var Bitmap := TBitmap.Create;
    try
      Bitmap.SetSize(List.Width,List.Height); List.PaintTo(Bitmap.Canvas,0,0);
      var R := List.ItemRect(Index);
      var Color := ColorToRGB(Bitmap.Canvas.Pixels[4,(R.Top+R.Bottom) div 2]);
      var Expected: TColor := $00202020;
      if Active then Expected := $003D5030;
      if List.ItemIndex=Index then begin Expected := $00D07000; if Active then Expected := $00507628; end;
      if Color<>ColorToRGB(Expected) then begin
        Writeln('COLOR actual=',IntToHex(Color,8),' expected=',IntToHex(ColorToRGB(Expected),8),
          ' top=',R.Top,' bottom=',R.Bottom,' listPPI=',List.CurrentPPI);
        var Png := TPngImage.Create;
        try Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(OutputRoot,'row-color-failure.png')); finally Png.Free; end;
      end;
      Check(Color=ColorToRGB(Expected),CaseName+' rendered row color '+Index.ToString);
    finally Bitmap.Free; end;
  end;
begin
  SelectRow(0);
  var List := Host.Frame.FindComponent('ScriptEffectKind') as TListBox;
  var Combo := Host.Frame.FindComponent('ScriptEffectPreset') as TComboBox;
  var Apply := Host.Frame.FindComponent('ScriptEffectApplyPreset') as TButton;
  Check(List.Items.Count=20,'twenty effect types in listbox');
  Check(Combo.Items.Count=18,'eighteen reference preset choices');
  var P := Host.Workspace.ScriptDraft;
  var OtherStamp := CueVoiceEffectsStamp(P.Cue(Cue1));
  var Export := TJSONArray.Create;
  try
    for var I := 0 to VOICE_EFFECT_PRESET_COUNT-1 do begin
      Check(Combo.Items[I]=VoiceEffectPresetName(I),'preset name '+I.ToString);
      var Before := CueVoiceEffectsStamp(P.Cue(Cue0));
      Combo.ItemIndex := I; Pump(20);
      Check(CueVoiceEffectsStamp(P.Cue(Cue0))=Before,'selection alone preserves cue '+I.ToString);
      Adopt(I);
      var Expected := CreateVoiceEffectPreset(I);
      try
        Check(CueVoiceEffectsStamp(P.Cue(Cue0))=VoiceEffectSettingsStamp(Expected),'button adopts complete preset '+I.ToString);
        Check(Expected.Count=100,'preset covers all one hundred parameters '+I.ToString);
      finally Expected.Free; end;
      Check(CueVoiceEffectsStamp(P.Cue(Cue1))=OtherStamp,'preset leaves other cue unchanged '+I.ToString);
      var Entry := TJSONObject.Create; Export.AddElement(Entry);
      AddN(Entry,'index',I); Entry.AddPair('name',Combo.Items[I]);
      Entry.AddPair('settings',P.Cue(Cue0).AudioEffects.Clone as TJSONObject);
    end;
    TFile.WriteAllText(TPath.Combine(OutputRoot,'adopted-presets.json'),Export.ToJSON,TEncoding.UTF8);
  finally Export.Free; end;
  Adopt(5); List.TopIndex := 0;
  var ClickRow := List.ItemRect(0);
  List.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(8,(ClickRow.Top+ClickRow.Bottom) div 2));
  List.Perform(WM_LBUTTONUP,0,MakeLParam(8,(ClickRow.Top+ClickRow.Bottom) div 2)); Pump(20);
  Check((List.ItemIndex=0) and not (Host.Frame.FindComponent('ScriptEffectOn') as TAul2LampSwitch).Checked,
    'native list click selects Delay controls');
  List.Perform(WM_KEYDOWN,VK_DOWN,0); List.Perform(WM_KEYUP,VK_DOWN,0); Pump(20);
  Check((List.ItemIndex=1) and (Host.Frame.FindComponent('ScriptEffectOn') as TAul2LampSwitch).Checked,
    'native arrow key selects enabled EQ controls');
  CheckRowColor(1,True,'preset selected ON');
  SelectEffect(0); CheckRowColor(1,True,'preset unselected ON'); CheckRowColor(0,False,'preset selected OFF');
  var Lamp := Host.Frame.FindComponent('ScriptEffectOn') as TAul2LampSwitch;
  Lamp.Checked := True; Lamp.OnClick(Lamp); Pump(20); CheckRowColor(0,True,'manual switch ON');
  Lamp.Checked := False; Lamp.OnClick(Lamp); Pump(20); CheckRowColor(0,False,'manual switch OFF');
  SelectRow(1); CheckRowColor(1,False,'other cue OFF'); SelectRow(0); CheckRowColor(1,True,'return restores ON');
  SelectEffect(18); SetGain(-8);
  var Edit := VolumeEdit(Host.Frame.FindComponent('ScriptEffectValue0') as TAul2VolumeControl);
  Edit.Text := 'invalid'; SelectEffect(1);
  Check(List.ItemIndex=18,'invalid knob input retains previous effect');
  Adopt(0);
  Check(not VoiceEffectsEnabled(P.Cue(Cue0).AudioEffects),'none disables every effect');
  Check(VoiceEffectValue(P.Cue(Cue0).AudioEffects,'Out: Gain(dB)')=0,'none replaces manual and pending values with defaults');
  Check(Host.Frame.RequestFinish,'none clears invalid numeric input');
  Adopt(6); var SavedStamp := CueVoiceEffectsStamp(P.Cue(Cue0));
  Host.Workspace.SaveScriptDraft; Host.Workspace.OpenScriptDraft(SavedPath); Pump(50);
  P := Host.Workspace.ScriptDraft;
  Check(CueVoiceEffectsStamp(P.Cue(Cue0))=SavedStamp,'preset settings survive save and reopen');
  for var PPI in [96,144,192,96] do begin
    Host.Form.Scaled := True; Host.Form.ScaleForPPI(PPI); Host.Form.Scaled := False;
    Host.Form.ClientWidth := MulDiv(1280,PPI,96); Host.Form.ClientHeight := MulDiv(800,PPI,96);
    Host.Layout; Pump(60);
    var Rows := Host.Frame.FindComponent('ScriptVoiceEffectsRows') as TListView;
    var RowPos := Rows.ClientToScreen(Point(Rows.Width,0));
    var ListPos := List.ClientToScreen(Point(0,0)); var SettingsPos := Combo.ClientToScreen(Point(0,0));
    Check((RowPos.X<=ListPos.X) and (ListPos.X+List.Width<=SettingsPos.X),'cue-list-settings order '+PPI.ToString);
    Check((Apply.Left+Apply.Width<Combo.Left) and (Apply.Top=Combo.Top),'adopt button left of combo '+PPI.ToString);
    Check(List.ItemHeight=MulDiv(26,PPI,96),'list row scales with DPI '+PPI.ToString);
    SelectEffect(19); CheckRowColor(19,True,'last effect scroll '+PPI.ToString);
    SelectEffect(1); List.TopIndex := 0; CheckRowColor(1,True,'saved preset ON '+PPI.ToString);
    Capture('preset-layout-'+PPI.ToString);
  end;
  Adopt(0); SelectEffect(0);
  Button('ScriptEffectsLoop').Execute;
  WaitFor('preset audition loop begins',function: Boolean begin Result := PreviewReady(Cue0) and PlayOpened(True); end);
  var OriginalPreview := P.Cue(Cue0).EffectAudioKey;
  Adopt(6);
  Check(CueEffectPreviewKey(P,P.Cue(Cue0))<>OriginalPreview,'adoption invalidates old preview settings');
  WaitFor('loop adopts telephone preset',function: Boolean begin Result := PreviewReady(Cue0) and PlayOpened(True) and MeasuredCurrent; end);
  Adopt(0);
  WaitFor('loop adopts reset defaults',function: Boolean begin Result := PreviewReady(Cue0) and PlayOpened(True) and MeasuredCurrent; end);
  Button('ScriptEffectsStop').Execute; Pump(50); Check(not StopEnabled,'preset loop stops normally');
end;

procedure CheckPlayback;
begin
  Host.Form.ClientWidth := 1400; Host.Form.ClientHeight := 900; Host.Layout; Pump(100);
  SelectRow(0); SelectEffect(18);
  Button('ScriptEffectsPlay').Execute;
  WaitFor('normal preview is published and playing',function: Boolean begin Result := PreviewReady(Cue0) and StopEnabled and PlayOpened(False); end);
  Capture('effects-normal-playing');
  WaitFor('normal preview reaches end',function: Boolean begin Result := not StopEnabled; end);

  Button('ScriptEffectsLoop').Execute;
  WaitFor('loop starts',function: Boolean begin Result := PreviewReady(Cue0) and StopEnabled and PlayOpened(True); end);
  Pump(2200); Check(StopEnabled,'loop survives first duration');
  var Lamp := Host.Frame.FindComponent('ScriptEffectOn') as TAul2LampSwitch;
  Lamp.Checked := True; Lamp.OnClick(Lamp); SetGain(-6);
  Check(Abs(VoiceEffectValue(Host.Workspace.ScriptDraft.Cue(Cue0).AudioEffects,'Out: Gain(dB)')+6)<0.0001,'playback edit updates only selected cue settings');
  WaitFor('loop adopts latest settings at next render',function: Boolean begin Result := PreviewReady(Cue0) and StopEnabled and PlayOpened(True) and MeasuredCurrent; end);
  Capture('effects-loop-measured');
  Button('ScriptEffectsStop').Execute; Pump(200); Check(not StopEnabled,'stop clears active loop');
  Check(MeasuredCurrent,'stop retains completed waveform measurement');

  Button('ScriptEffectsLoop').Execute;
  WaitFor('loop restarts',function: Boolean begin Result := StopEnabled and PlayOpened(True); end);
  SelectRow(1); Check(not StopEnabled,'row change stops previous audition');
  Check(not VoiceEffectsEnabled(Host.Workspace.ScriptDraft.Cue(Cue1).AudioEffects),'row change does not copy previous cue settings');
  Button('ScriptEffectsPlay').Execute;
  WaitFor('second cue preview is independent',function: Boolean begin Result := PreviewReady(Cue1) and StopEnabled and PlayOpened(False); end);
  Host.Frame.SetActive(False); Pump(150); Check(not StopEnabled,'stage deactivation stops audition');
  Host.Frame.SetActive(True); Pump(150);

  var ActiveSource := ResolveMoviePath(Host.Workspace.ScriptDraft.FileName,Host.Workspace.ScriptDraft.Cue(Cue1).WaveFile);
  var MissingPath := ActiveSource+'.owned-missing';
  Check(RenameFile(ActiveSource,MissingPath),'test-owned source can be isolated as missing');
  try
    Host.Frame.RefreshState; Pump(120);
    Check(not Enabled(Button('ScriptEffectsPlay')),'missing source disables playback');
    Check(not StopEnabled,'missing source leaves audition stopped');
  finally Check(RenameFile(MissingPath,ActiveSource),'test-owned source restored'); end;
  Host.Frame.RefreshState; Pump(120); Check(Enabled(Button('ScriptEffectsPlay')),'source restoration re-enables playback');
  Button('ScriptEffectsPlay').Execute;
  WaitFor('playback recovers after missing source',function: Boolean begin Result := PreviewReady(Cue1) and StopEnabled and PlayOpened(False); end);
  Button('ScriptEffectsStop').Execute; Pump(150);

  SelectRow(0); SelectEffect(18);
  var Volume := Host.Frame.FindComponent('ScriptEffectValue0') as TAul2VolumeControl;
  var Edit := VolumeEdit(Volume); Edit.Text := 'invalid';
  Check(not Host.Frame.RequestFinish,'invalid numeric draft blocks save/Next boundary');
  Edit.Text := '-4.0'; Check(Host.Frame.RequestFinish,'valid numeric draft commits at save/Next boundary');
  Check(Abs(VoiceEffectValue(Host.Workspace.ScriptDraft.Cue(Cue0).AudioEffects,'Out: Gain(dB)')+4)<0.0001,'finish uses pending numeric draft');
  Host.Workspace.SaveScriptDraft;
  var SettingsStamp := CueVoiceEffectsStamp(Host.Workspace.ScriptDraft.Cue(Cue0));
  Host.Workspace.OnScriptChanged := nil; FreeAndNil(Host.Frame); FreeAndNil(Host.Workspace);
  Host.Workspace := TRigmWizardWorkspace.Create(nil); Host.Workspace.StartPipe(FixtureRoot);
  Host.Workspace.OpenScriptDraft(SavedPath);
  Check(Host.Workspace.CurrentScriptStage='voice-effects','fresh workspace reopens saved effect stage');
  Check(CueVoiceEffectsStamp(Host.Workspace.ScriptDraft.Cue(Cue0))=SettingsStamp,'per-cue settings survive fresh reopen');
  Host.Frame := TRigmScriptVoiceEffectsFrame.CreateForWorkspace(Host.Canvas,Host.Workspace);
  Host.Workspace.OnScriptChanged := Host.Changed; Host.Frame.SetActive(True); Host.Layout; Pump(200);
  Check(JS(JO(Host.Workspace.ScriptDraft.ScriptWizard,'voiceEffects'),'selectedCue')=Cue0,'selected stable cue survives reopen');
  Button('ScriptEffectsPlay').Execute;
  WaitFor('reopened settings render and play',function: Boolean begin Result := PreviewReady(Cue0) and StopEnabled and PlayOpened(False); end);
  Button('ScriptEffectsStop').Execute; Pump(200);

  Check(Host.Frame.RequestFinish,'effect frame finishes before Next'); Host.Workspace.NextScriptDraft;
  Check(Host.Workspace.CurrentScriptStage='scene-assignment','Next reaches scene assignment');
  Check(JS(Host.Workspace.ScriptDraft.ScriptWizard,'voice-effectsStatus')='complete','Next saves effects completion');
  var Loaded := LoadMovie(SavedPath);
  try
    Check(JS(Loaded.ScriptWizard,'stage')='scene-assignment','Next transition persists to disk');
    Check(CueVoiceEffectsStamp(Loaded.Cue(Cue0))=SettingsStamp,'Next preserves per-cue effects');
  finally Loaded.Free; end;
end;

procedure CheckLongAudioPaths;
begin
  var LongRoot := TPath.Combine(OutputRoot,'long owned '+string(Char($65E5))+Char($672C)+Char($8A9E));
  while Length(LongRoot)<300 do LongRoot := TPath.Combine(LongRoot,'nested Unicode space '+StringOfChar('x',38));
  var LongSource := TPath.Combine(LongRoot,string(Char($65E5))+Char($672C)+Char($8A9E)+' PCM fixture.wav');
  WriteWave(LongSource,220);
  Check(Length(LongSource)>300,'owned Unicode PCM source exceeds 300 characters');
  Check(AudioFileExists(LongSource),'extended Unicode source exists');
  var HashBefore := THashSHA2.GetHashStringFromFile(AudioFilePath(LongSource));
  var Audio := TRigmPcm.Load(LongSource);
  try
    Check((Audio.Rate=24000) and (Length(Audio.Samples)=36000),'PCM loads source beyond MAX_PATH');
    var LongCopy := TPath.Combine(LongRoot,'saved PCM copy.wav');
    Audio.Save(LongCopy);
    Check(THashSHA2.GetHashStringFromFile(AudioFilePath(LongCopy))=HashBefore,'PCM save beyond MAX_PATH preserves samples');
  finally Audio.Free; end;
  var P := Host.Workspace.ScriptDraft.Clone;
  try
    var C := P.Cue(Cue0); C.WaveFile := LongSource;
    C.AudioKey := P.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
    var DerivedParent := TPath.Combine(OutputRoot,'derived '+StringOfChar('d',218-Length(OutputRoot)-9));
    P.FileName := TPath.Combine(DerivedParent,'project.rigmovie');
    Check(Length(P.FileName)<260,'long audio test project reference stays below MAX_PATH');
    Check(P.AudioReady(C),'AudioReady accepts current long Unicode source');
    Check(CueEffectSourceStamp(P,C)<>'','long source metadata fingerprint is available');
    var OriginalTime := TFile.GetLastWriteTimeUtc(AudioFilePath(LongSource));
    var SourceStamp := CueEffectSourceStamp(P,C);
    var MixStamp := MovieAudioStamp(P);
    try
      TFile.SetLastWriteTimeUtc(AudioFilePath(LongSource),OriginalTime+1/(24*60));
      Check(CueEffectSourceStamp(P,C)<>SourceStamp,'long source timestamp invalidates preview metadata');
      Check(MovieAudioStamp(P)<>MixStamp,'long source timestamp invalidates final mix metadata');
    finally TFile.SetLastWriteTimeUtc(AudioFilePath(LongSource),OriginalTime); end;
    var Job := TRigmVoiceEffectsPreviewJob.Create(P,C.Id);
    var AdoptedPath: string;
    try
      Job.Start;
      WaitFor('long-source derived preview job completes',function: Boolean begin Result := Job.Done; end,12000);
      Check(Job.Error='','long-source preview has no error: '+Job.Error);
      Check(Length(Job.FileName)>260,'derived preview path exceeds MAX_PATH');
      Check(AudioFileExists(Job.FileName),'derived long preview file exists');
      var Analysis := Job.DetachAnalysis;
      try Check((Analysis<>nil) and Analysis.Ready,'long derived preview publishes sealed measurements'); finally Analysis.Free; end;
      C.EffectWaveFile := Job.FileName; C.EffectAudioKey := Job.Key;
      AdoptedPath := Job.FileName;
      Job.KeepOutput;
    finally Job.Free; end;
    Check(AudioFileExists(AdoptedPath),'adopted long preview survives job destruction');
    Job := TRigmVoiceEffectsPreviewJob.Create(P,C.Id);
    var DiscardedPath: string;
    try
      Job.Start;
      WaitFor('unadopted preview job completes',function: Boolean begin Result := Job.Done; end,12000);
      Check(Job.Error='','unadopted preview has no error: '+Job.Error);
      DiscardedPath := Job.FileName;
      Check(AudioFileExists(DiscardedPath),'unadopted preview exists before job destruction');
    finally Job.Free; end;
    Check(not AudioFileExists(DiscardedPath),'unadopted preview is removed at job destruction');
    var StoreRoot := TPath.Combine(OutputRoot,StringOfChar('s',181-Length(OutputRoot)-1));
    var StoreFile := TPath.Combine(StoreRoot,'project.rigmovie');
    ForceDirectories(StoreRoot);
    Check((Length(StoreFile)<216) and (Length(StoreFile)>190),'owned store JSON and atomic temporary paths stay below MAX_PATH');
    SaveMovie(P,StoreFile,False);
    var Loaded := LoadMovie(StoreFile);
    try
      var StoredSource := ResolveMoviePath(Loaded.FileName,Loaded.Cue(Cue0).WaveFile);
      var StoredEffect := ResolveMoviePath(Loaded.FileName,Loaded.Cue(Cue0).EffectWaveFile);
      Writeln('LONG source=',Length(LongSource),' derived=',Length(ResolveMoviePath(P.FileName,P.Cue(Cue0).EffectWaveFile)),
        ' storeProject=',Length(StoreFile),' managedSource=',Length(StoredSource),' managedEffect=',Length(StoredEffect));
      Check(Length(StoredSource)>260,'hashed managed source target exceeds MAX_PATH');
      Check(Length(StoredEffect)>260,'hashed managed effect target exceeds MAX_PATH');
      Check(Loaded.AudioReady(Loaded.Cue(Cue0)),'reopened long managed source is audio ready');
      Check(AudioFileExists(StoredEffect),'reopened long managed preview exists');
      Check(THashSHA2.GetHashStringFromFile(AudioFilePath(StoredSource))=HashBefore,'long managed copy verifies original PCM hash');
    finally Loaded.Free; end;
    Check(THashSHA2.GetHashStringFromFile(AudioFilePath(LongSource))=HashBefore,'long source remains unchanged after processing and store');
  finally P.Free; end;
end;

procedure WriteReports;
begin
  TFile.WriteAllText(TPath.Combine(OutputRoot,'checks.json'),Checks.ToJSON,TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(OutputRoot,'bounds.json'),Bounds.ToJSON,TEncoding.UTF8);
  var Summary := TJSONObject.Create;
  try
    AddN(Summary,'checks',Checks.Count); Summary.AddPair('error',UnhandledError);
    Summary.AddPair('fixtureRoot',FixtureRoot); Summary.AddPair('project',SavedPath);
    Summary.AddPair('sourceHash0',SourceHash0); Summary.AddPair('sourceHash1',SourceHash1);
    Summary.AddPair('manuscriptHash',ManuscriptHash);
    TFile.WriteAllText(TPath.Combine(OutputRoot,'summary.json'),Summary.ToJSON,TEncoding.UTF8);
  finally Summary.Free; end;
end;

begin
  SetTextCodePage(System.Output,CP_UTF8);
  Checks := TJSONArray.Create; Bounds := TJSONArray.Create; Host := TProbeHost.Create;
  try
    try
      var AllowedRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ExtractFileDir(ParamStr(0)),'..')));
      var CandidateRoot := TPath.GetFullPath(ParamStr(1));
      if not CandidateRoot.StartsWith(AllowedRoot,True) then raise Exception.Create('Probe output must stay under its isolated validation folder');
      OutputRoot := CandidateRoot;
      if Length(OutputRoot)>150 then raise Exception.Create('Use a shorter isolated output root (at most 150 characters) for controlled MAX_PATH fixtures');
      ForceDirectories(OutputRoot); FixtureRoot := TPath.Combine(OutputRoot,'w-'+PsdJson.NewId.Replace('{','').Replace('}','').Substring(0,8));
      ForceDirectories(FixtureRoot); ForceDirectories(TPath.Combine(OutputRoot,'settings'));
      if not SetEnvironmentVariable('RIGMMAKER_SETTINGS_DIR',PChar(TPath.Combine(OutputRoot,'settings'))) then RaiseLastOSError;
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
      Application.Initialize; Application.MainFormOnTaskbar := False;
      Application.OnException := Host.GuiException;
      Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'production dark VCL style loaded');
      Host.Form := TForm.CreateScaledNew(nil,96); Host.Form.Scaled := False;
      Host.Form.Font.PixelsPerInch := 96; Host.Form.Font.IsDPIRelated := True;
      Host.Form.Font.Name := 'Yu Gothic UI'; Host.Form.Font.Size := 10;
      Host.Form.Caption := 'RIGMMaker owned effects validation'; Host.Form.Position := poDesigned;
      Host.Form.SetBounds(0,0,1420,950);
      Host.Stage := TScrollBox.Create(Host.Form); Host.Stage.Parent := Host.Form;
      Host.Stage.Align := alClient; Host.Stage.BorderStyle := bsNone;
      Host.Stage.HorzScrollBar.Tracking := True; Host.Stage.VertScrollBar.Tracking := True;
      Host.Canvas := TPanel.Create(Host.Form); Host.Canvas.Parent := Host.Stage;
      Host.Canvas.BevelOuter := bvNone; Host.Canvas.Caption := ''; Host.Form.OnResize := Host.Resize;
      Host.Workspace := TRigmWizardWorkspace.Create(nil); PrepareFixture;
      Host.Frame := TRigmScriptVoiceEffectsFrame.CreateForWorkspace(Host.Canvas,Host.Workspace);
      Host.Workspace.OnScriptChanged := Host.Changed; Host.Layout;
      ShowWindow(Host.Form.Handle,SW_SHOWNOACTIVATE); Host.Form.Visible := True;
      Host.Frame.SetActive(True); Host.Form.Update; Pump(200);
      Check(AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(Host.Form.Handle),
        DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2),'owned host uses PerMonitorV2');
      CheckPresets; CheckLayout;
      if ParamStr(2)<>'--presets-only' then begin CheckPlayback; CheckLongAudioPaths; end;
      Check(THashSHA2.GetHashStringFromFile(Source0)=SourceHash0,'original PCM one remains unchanged');
      Check(THashSHA2.GetHashStringFromFile(Source1)=SourceHash1,'original PCM two remains unchanged');
      Check(ScriptFingerprint(Host.Workspace.ScriptDraft)=ManuscriptHash,'full UI/playback/Next run preserves manuscript');
      Writeln('PASS checks=',Checks.Count);
    except on E: Exception do begin
      UnhandledError := E.ClassName+': '+E.Message; Writeln('FAIL ',UnhandledError); ExitCode := 1;
    end; end;
    if OutputRoot<>'' then WriteReports;
  finally
    Application.OnException := nil;
    if Host.Workspace<>nil then Host.Workspace.OnScriptChanged := nil;
    Host.Frame.Free; Host.Workspace.Free; Host.Form.Free; Host.Free; Bounds.Free; Checks.Free;
  end;
end.
