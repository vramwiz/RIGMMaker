program RigmInteractionTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types,
  System.Diagnostics, System.StrUtils, System.Math, System.Generics.Collections, Vcl.Forms, Vcl.Controls,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Themes, Vcl.Styles,
  Winapi.Windows, Winapi.Messages, ArtDocument, ArtLayerList,
  RigmEditorForm, RigmModel, RigmJson;

type
  TPaintCounter = class
    Count: Integer;
    Original: TNotifyEvent;
    procedure Paint(Sender: TObject);
  end;

var Checks: TJSONArray; Passed: Integer; TestDirectory: string;

procedure TPaintCounter.Paint(Sender: TObject);
begin Inc(Count); if Assigned(Original) then Original(Sender); end;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Passed); Writeln('PASS: ' + Name); Checks.Add(Name);
end;

function FindControl(Parent: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to Parent.ControlCount - 1 do begin
    var Control := Parent.Controls[I];
    if Control.Name = Name then Exit(Control);
    if Control is TWinControl then begin
      Result := FindControl(TWinControl(Control), Name); if Result <> nil then Exit;
    end;
  end;
end;

function Benchmark(Form: TRigmEditorForm): TJSONObject;
const Iterations = 120;
var List: TArtLayerList; Images: TList<TArtLayer>; Times: TArray<Double>;
    Counter: TPaintCounter; Preview: TPaintBox; Start: Int64; Controls: TControl;
    Replaced: Integer; Total: Double; Modes: TJSONArray;
begin
  Result := TJSONObject.Create; Images := TList<TArtLayer>.Create; Counter := TPaintCounter.Create;
  try
    List := TArtLayerList(FindControl(Form, 'LayerList'));
    for var L in Form.Editor.Document.Layers do if L.Kind = alkImage then Images.Add(L);
    Preview := TPaintBox(FindControl(Form, 'CharacterPreview'));
    Counter.Original := Preview.OnPaint; Preview.OnPaint := Counter.Paint;
    Result.AddPair('fixture', Form.Editor.Document.PsdSourceName);
    AddN(Result, 'imageCount', Images.Count); AddN(Result, 'iterationsPerMode', Iterations);
    AddN(Result, 'windowWidth', Form.Width); AddN(Result, 'windowHeight', Form.Height);
    Result.AddPair('style', TStyleManager.ActiveStyle.Name);
    Modes := TJSONArray.Create; Result.AddPair('modes', Modes);
    for var Pump := 0 to 1 do begin
      for var L in Images do begin List.Selected := L; Application.ProcessMessages; end;
      Counter.Count := 0; Replaced := 0; Total := 0; SetLength(Times, Iterations);
      for var I := 0 to Iterations - 1 do begin
        Controls := FindControl(Form, 'Fieldname');
        Start := TStopwatch.GetTimeStamp;
        List.Selected := Images[I mod Images.Count];
        if Pump = 1 then Application.ProcessMessages;
        Times[I] := (TStopwatch.GetTimeStamp - Start) * 1000.0 / TStopwatch.Frequency;
        Total := Total + Times[I];
        if FindControl(Form, 'Fieldname') <> Controls then Inc(Replaced);
      end;
      TArray.Sort<Double>(Times);
      var Mode := TJSONObject.Create; Modes.Add(Mode);
      Mode.AddPair('mode', 'selection-event' + IfThen(Pump = 1, '-and-message-pump', ''));
      AddN(Mode, 'totalMs', Total); AddN(Mode, 'medianMs', Times[Iterations div 2]);
      AddN(Mode, 'p95Ms', Times[Round(Iterations * 0.95) - 1]);
      AddN(Mode, 'previewPaints', Counter.Count); AddN(Mode, 'nameControlsReplaced', Replaced);
    end;
    Preview.OnPaint := Counter.Original;
  finally Counter.Free; Images.Free; end;
end;

procedure BringIntoView(Box: TScrollBox; Control: TControl);
begin
  Box.VertScrollBar.Position := EnsureRange(Box.VertScrollBar.Position + Control.Top - Box.ClientHeight div 2,
    0, Max(0, Box.VertScrollBar.Range - Box.ClientHeight));
  Application.ProcessMessages;
end;

procedure Wheel(Control: TWinControl; Delta: Integer);
var P: TPoint;
begin
  if Control is TScrollBox then P := Control.ClientToScreen(Point(Control.ClientWidth - 24, 60))
  else P := Control.ClientToScreen(Point(Control.ClientWidth div 2, Control.ClientHeight div 2));
  PostMessage(Control.Handle, WM_MOUSEWHEEL, WPARAM(Cardinal(Word(SmallInt(Delta))) shl 16),
    LPARAM(Cardinal(Word(P.X)) or (Cardinal(Word(P.Y)) shl 16)));
  Application.ProcessMessages;
end;

procedure InteractionChecks(Form: TRigmEditorForm);
var List: TArtLayerList; Box: TScrollBox; Images: TList<string>;
    NameEdit, XEdit: TEdit; RoleCombo, ParentCombo, PairCombo: TComboBox; XSlider: TTrackBar;
    Revision: UInt64; Position, Index, ControlCount: Integer; Id, OtherId: string;
    NamesCorrect, ValuesCorrect, Stable: Boolean; Reply, Args: TJSONObject;
begin
  Images := TList<string>.Create;
  try
    List := TArtLayerList(FindControl(Form, 'LayerList'));
    Box := TScrollBox(FindControl(Form, 'PropertyScrollBox'));
    for var Layer in Form.Editor.Document.Layers do if Layer.Kind = alkImage then Images.Add(Layer.Id);
    Id := Images[0]; OtherId := Images[1];
    List.Selected := Form.Editor.Document.Art.FindLayer(Id); Application.ProcessMessages;
    NameEdit := TEdit(FindControl(Form, 'Fieldname'));
    XEdit := TEdit(FindControl(Form, 'Fieldx')); XSlider := TTrackBar(FindControl(Form, 'Sliderx'));
    RoleCombo := TComboBox(FindControl(Form, 'Comborole'));
    ControlCount := Box.ControlCount; Revision := Form.Editor.Document.Art.Revision;
    Box.VertScrollBar.Position := 120; Position := Box.VertScrollBar.Position;
    NamesCorrect := True; ValuesCorrect := True; Stable := True;
    for var Pass := 0 to 2 do for var LayerId in Images do begin
      var L := Form.Editor.Document.Art.FindLayer(LayerId); var P := Form.Editor.Document.Part(LayerId);
      List.Selected := L; Application.ProcessMessages;
      NamesCorrect := NamesCorrect and (NameEdit.Text = L.Name) and
        (TEdit(FindControl(Form, 'Fieldid')).Text = L.Id);
      ValuesCorrect := ValuesCorrect and StartsText(P.Role + ' ', RoleCombo.Text) and
        SameValue(StrToFloat(XEdit.Text, TFormatSettings.Invariant), P.X) and
        (TCheckBox(FindControl(Form, 'Checkvisible')).Checked = L.Visible);
      Stable := Stable and (FindControl(Form, 'Fieldname') = NameEdit) and
        (FindControl(Form, 'Fieldx') = XEdit) and (FindControl(Form, 'Comborole') = RoleCombo);
    end;
    Check(NamesCorrect, '117 consecutive image selections display the matching name and id');
    Check(ValuesCorrect, 'selection updates roles, numeric values, and visibility correctly');
    Check(Stable and (Box.ControlCount <= ControlCount + 2), 'selection reuses controls without growing the property tree');
    Check((Box.VertScrollBar.Position = Position) and (NameEdit.Top < 0), 'selection preserves scroll position and logical field placement');
    Check((Form.Editor.Document.Art.Revision = Revision) and not Form.Editor.Document.SourceMatched,
      'selection does not edit the document or confirm human review');
    List.Selected := Form.Editor.Document.Art.FindLayer(Id); Application.ProcessMessages;
    NameEdit.Text := '未適用の編集'; List.OnSelect(List); Application.ProcessMessages;
    Check(NameEdit.Text = '未適用の編集', 'reselecting the same part preserves unapplied text');
    List.Selected := Form.Editor.Document.Art.FindLayer(OtherId); List.Selected := Form.Editor.Document.Art.FindLayer(Id);
    Application.ProcessMessages;
    Check((Box.VertScrollBar.Range > Box.ClientHeight) and not Box.HorzScrollBar.Visible,
      'properties have a vertical scroll range without horizontal scrolling');

    Box.VertScrollBar.Position := 0; Position := Box.VertScrollBar.Position; Wheel(Box, -WHEEL_DELTA);
    var Lines: Cardinal := 3; SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, @Lines, 0);
    Check((Lines = 0) or (Box.VertScrollBar.Position > Position), 'wheel over property background scrolls vertically');
    XEdit.SetFocus; var Focus := Form.ActiveControl;
    BringIntoView(Box, RoleCombo); Position := Box.VertScrollBar.Position; Index := RoleCombo.ItemIndex;
    Wheel(RoleCombo, -WHEEL_DELTA);
    Check((Lines = 0) or (Box.VertScrollBar.Position > Position), 'wheel over an unfocused combo scrolls the property panel');
    Check((RoleCombo.ItemIndex = Index) and (Form.ActiveControl = Focus), 'combo wheel preserves the selected role and keyboard focus');
    BringIntoView(Box, XSlider); Position := Box.VertScrollBar.Position; Index := XSlider.Position;
    var NumericText := XEdit.Text; Wheel(XSlider, -WHEEL_DELTA);
    Check(Box.VertScrollBar.Position = Position, 'wheel over a numeric slider keeps the property panel position');
    Check((XSlider.Position = Max(XSlider.Min,Index-1)) and (XEdit.Text = IntToStr(XSlider.Position)) and (Form.ActiveControl = Focus), 'slider wheel finely adjusts only its pending numeric value without changing focus');
    NumericText := XEdit.Text;
    BringIntoView(Box, XEdit); Position := Box.VertScrollBar.Position; Wheel(XEdit, -WHEEL_DELTA);
    Check(((Lines = 0) or (Box.VertScrollBar.Position > Position)) and (XEdit.Text = NumericText),
      'wheel over an edit scrolls without changing its text');
    BringIntoView(Box, RoleCombo); Position := Box.VertScrollBar.Position;
    Wheel(RoleCombo, -WHEEL_DELTA div 2);
    Check(Box.VertScrollBar.Position = Position, 'half wheel delta is retained until a full step');
    Wheel(RoleCombo, -WHEEL_DELTA div 2);
    Check((Lines = 0) or (Box.VertScrollBar.Position > Position), 'two half deltas produce one scroll step');
    var VisibleCheck := TCheckBox(FindControl(Form, 'Checkvisible'));
    BringIntoView(Box, VisibleCheck); Position := Box.VertScrollBar.Position; var WasChecked := VisibleCheck.Checked;
    // A taller viewport can place this lower field at the end of the scroll range.
    // Exercise a direction with room to move instead of confusing a boundary with a lost wheel event.
    if Position = Max(0, Box.VertScrollBar.Range - Box.ClientHeight) then Wheel(VisibleCheck, WHEEL_DELTA)
    else Wheel(VisibleCheck, -WHEEL_DELTA);
    Check(((Lines = 0) or (Box.VertScrollBar.Position <> Position)) and (VisibleCheck.Checked = WasChecked),
      'wheel over a checkbox scrolls without toggling visibility');
    Position := Box.VertScrollBar.Position;
    var ListPosition := List.ScrollBar.Position; Wheel(List, -WHEEL_DELTA);
    Check((Box.VertScrollBar.Position = Position) and (List.ScrollBar.Position > ListPosition),
      'wheel over the layer list scrolls only the layer list');
    Box.VertScrollBar.Position := 0; Wheel(Box, WHEEL_DELTA);
    Check(Box.VertScrollBar.Position = 0, 'wheel stops at the top boundary');
    Box.VertScrollBar.Position := Max(0, Box.VertScrollBar.Range - Box.ClientHeight); Position := Box.VertScrollBar.Position;
    Wheel(Box, -WHEEL_DELTA); Check(Box.VertScrollBar.Position = Position, 'wheel stops at the bottom boundary');
    Check(Form.Editor.Document.Art.Revision = Revision, 'wheel scrolling leaves document revision unchanged');

    Box.VertScrollBar.Position := 0;
    NameEdit.Text := 'UI手動編集'; XEdit.Text := '12.5';
    for Index := 0 to RoleCombo.Items.Count - 1 do if RoleCombo.Items[Index].StartsWith('other ') then RoleCombo.ItemIndex := Index;
    TButton(FindControl(Form, 'ApplyLayerPropertiesButton')).Click; Application.ProcessMessages;
    Check((Form.Editor.Document.Art.FindLayer(Id).Name = 'UI手動編集') and
      SameValue(Form.Editor.Document.Part(Id).X, 12.5) and Form.Editor.Document.Part(Id).RoleManual,
      'reused controls apply manual name, fractional coordinate, and role edits');
    Check((FindControl(Form, 'Fieldname') = NameEdit) and (XEdit.Text = '12.5'),
      'committing a model clone retains controls and the exact numeric text');
    List.Selected := Form.Editor.Document.Art.FindLayer(OtherId); Application.ProcessMessages;
    ParentCombo := TComboBox(FindControl(Form, 'ComboparentId'));
    var ParentId := Form.Editor.Document.ParentId(OtherId); var CurrentParent := '';
    if ParentCombo.ItemIndex > 0 then CurrentParent := TArtLayer(ParentCombo.Items.Objects[ParentCombo.ItemIndex]).Id;
    Check(CurrentParent = ParentId, 'parent selector refreshes model references after a commit');
    PairCombo := TComboBox(FindControl(Form, 'CombopairId'));
    for Index := 1 to PairCombo.Items.Count - 1 do
      if TArtLayer(PairCombo.Items.Objects[Index]).Id = Id then PairCombo.ItemIndex := Index;
    TButton(FindControl(Form, 'ApplyLayerPropertiesButton')).Click; Application.ProcessMessages;
    Check(Form.Editor.Document.Part(OtherId).PairId = Id, 'reused relationship combo applies ids from the current document');
    Args := TJSONObject.Create;
    try
      Args.AddPair('id', OtherId); Args.AddPair('name', '髪っぽい背景'); Args.AddPair('role', 'other');
      Reply := Form.Editor.Execute('update-layer', Args); Reply.Free;
    finally Args.Free; end;
    TToolButton(FindControl(Form, 'ClassifyLayersButton')).Click; Application.ProcessMessages;
    Check((Form.Editor.Document.Part(Id).Role = 'other') and Form.Editor.Document.Part(Id).RoleManual and
      (Form.Editor.Document.Part(OtherId).Role = 'other'), 'responsive UI retains manual roles and conservative classification');
    Check(not Form.Editor.Document.SourceMatched and not Form.Editor.Document.LayerComplete,
      'classification does not fabricate source confirmation or complete stages');

    var Second := TRigmEditorForm.Create(nil);
    try
      for var I := 0 to Second.ComponentCount - 1 do
        if Second.Components[I] is TTimer then TTimer(Second.Components[I]).Enabled := False;
      Second.OpenSample; Second.Show; Application.ProcessMessages;
      var SecondBox := TScrollBox(FindControl(Second, 'PropertyScrollBox'));
      var SecondSlider := TTrackBar(FindControl(Second, 'Sliderx'));
      BringIntoView(SecondBox, SecondSlider); Position := Box.VertScrollBar.Position;
      var SecondPosition := SecondBox.VertScrollBar.Position; Index := SecondSlider.Position;
      Wheel(SecondSlider, -WHEEL_DELTA);
      Check((SecondBox.VertScrollBar.Position = SecondPosition) and
        (Box.VertScrollBar.Position = Position) and (SecondSlider.Position = Max(SecondSlider.Min,Index-1)),
        'multiple editor message hooks finely adjust only the hovered window slider');
      Second.Editor.Save(TPath.Combine(TestDirectory, 'second.rigm'));
    finally Second.Free; end;
    Form.BringToFront; Application.ProcessMessages;
  finally Images.Free; end;
end;

procedure Run(var Metrics: TJSONObject);
const OriginalPsd = 'C:\Users\zan12\Documents\Syncroh2\PSD\Generated\東北きりたん_立ち絵.psd';
var Form: TRigmEditorForm; BenchmarkOnly: Boolean;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
  Form := TRigmEditorForm.Create(nil);
  try
    for var I := 0 to Form.ComponentCount - 1 do
      if Form.Components[I] is TTimer then TTimer(Form.Components[I]).Enabled := False;
    Form.OpenSeparatedPsd(OriginalPsd); Form.Show; Application.ProcessMessages;
    Metrics := Benchmark(Form);
    BenchmarkOnly := False;
    for var I := 1 to ParamCount do if ParamStr(I) = '--benchmark-only' then BenchmarkOnly := True;
    if not BenchmarkOnly then InteractionChecks(Form);
  finally Form.Free; end;
end;

var Metrics, Report: TJSONObject; ReportPath: string;
begin
  TestDirectory := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Interaction'); ForceDirectories(TestDirectory);
  ReportPath := TPath.Combine(TestDirectory, 'results.json');
  for var I := 1 to ParamCount do
    if ParamStr(I).StartsWith('--benchmark-report=') then ReportPath := ParamStr(I).Substring(19);
  Checks := TJSONArray.Create; Metrics := nil;
  try
    try Run(Metrics); except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    Report := TJSONObject.Create;
    try
      AddN(Report, 'passed', Passed); AddB(Report, 'success', ExitCode = 0);
      Report.AddPair('checks', Checks); Checks := nil;
      if Metrics <> nil then begin Report.AddPair('benchmark', Metrics); Metrics := nil; end;
      TFile.WriteAllText(ReportPath, Report.ToJSON, TEncoding.UTF8);
      Writeln('Report: ' + ReportPath);
    finally Report.Free; end;
  finally Metrics.Free; Checks.Free; end;
end.
