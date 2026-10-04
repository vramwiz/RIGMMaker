program RigmControllerTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  Winapi.Windows, GamepadState, GamepadNavigation, SwitchProInput, SwitchProOutput,
  SwitchProReportDecoder, RigmGamepadPreview, RigmModel, RigmJson;

var Count: Integer; Checks: TJSONArray;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then raise Exception.Create('FAIL: ' + Name);
  Inc(Count); Checks.Add(Name); Writeln('PASS: ' + Name);
end;

function FullReport(Id: Byte): TBytes;
begin
  SetLength(Result, 12); FillChar(Result[0], Length(Result), 0); Result[0] := Id;
  Result[7] := $08; Result[8] := $80; Result[10] := $08; Result[11] := $80;
end;

procedure RunProtocolTests;
var Report: TBytes; State: TGamepadState; Buttons, POV: Cardinal; Have: Boolean;
    Navigation: TGamepadNavigation; Frame: TGamepadFrame;
begin
  Report := BuildProSubcommandReport(64, 17, $30, $01);
  Check((Length(Report) = 64) and (Report[0] = $01) and (Report[1] = 1), 'copied HID output report and wrapped packet counter');
  Check((Report[3] = $01) and (Report[4] = $40) and (Report[5] = $40) and
    (Report[7] = $01) and (Report[8] = $40) and (Report[9] = $40), 'copied neutral rumble payload');
  Check((Report[10] = $30) and (Report[11] = $01), 'copied player LED command');
  Report := BuildProSubcommandReport(64, 0, $03, $30);
  Check((Report[10] = $03) and (Report[11] = $30), 'full report mode command');
  Report := BuildProSubcommandReport(64, 0, $03, $3F);
  Check((Report[10] = $03) and (Report[11] = $3F), 'normal mode restoration command');
  Check((Length(BuildProSubcommandReport(11, 0, 0, 0)) = 0) and
    (Length(BuildProSubcommandReport(4097, 0, 0, 0)) = 0), 'invalid output report lengths refused');
  State := TGamepadState.Neutral; Buttons := 0; POV := PadPOVNeutral; Have := False;
  Report := FullReport($30);
  Check(DecodeProReport(Report, Length(Report), State, Buttons, POV, Have) and
    Have and SameValue(State.LeftX, 0) and SameValue(State.LeftY, 0), 'full HID report neutral sticks');
  Report[3] := $CC; Report[4] := $0F; Report[5] := $C2;
  DecodeProReport(Report, Length(Report), State, Buttons, POV, Have);
  Check(State.Down(PadButtonA) and State.Down(PadButtonB) and State.Down(PadButtonR) and
    State.Down(PadButtonZR) and State.Down(PadButtonL) and State.Down(PadButtonZL), 'full HID face shoulder and trigger button mapping');
  Check(State.Down(PadButtonMinus) and State.Down(PadButtonPlus) and State.Down(PadButtonLeftStick) and
    State.Down(PadButtonRightStick) and (State.POV = 0), 'full HID menu stick and directional mapping');
  Report := FullReport($31); Report[6] := $FF; Report[7] := $0F; Report[8] := 0;
  Check(DecodeProReport(Report, 12, State, Buttons, POV, Have) and (State.LeftX > 0.99) and
    (State.LeftY < -0.99), '12-bit stick normalization and orientation');
  Check((Buttons and 2) <> 0, 'short button press retained across reports until poll');
  Report := FullReport($21); Check(DecodeProReport(Report, 12, State, Buttons, POV, Have), 'subcommand response input report supported');
  SetLength(Report, 12); FillChar(Report[0], 12, 0); Report[0] := $3F; Report[1] := $0F; Report[3] := 2;
  Report[5] := $80; Report[7] := $80; Report[9] := $80; Report[11] := $80;
  Check(DecodeProReport(Report, 12, State, Buttons, POV, Have) and State.Down(PadButtonX) and
    State.Down(PadButtonY) and (State.POV = 9000) and SameValue(State.RightY, 0), 'simple HID 3F report mapping and neutral axes');
  Report[6] := 0; Report[7] := 0; DecodeProReport(Report, 12, State, Buttons, POV, Have);
  Check(State.LeftY > 0.99, 'simple and full report vertical orientation matches');
  Report[0] := $7F; Check(not DecodeProReport(Report, 12, State, Buttons, POV, Have), 'unknown report does not refresh input');
  SetLength(Report, 2); Check(not DecodeProReport(Report, 12, State, Buttons, POV, Have), 'reported count beyond actual buffer refused');
  Check(not State.Down(0) and not State.Down(33), 'invalid button index is safe');
  Navigation := TGamepadNavigation.Create;
  try
    State := TGamepadState.Neutral; State.LeftX := 1;
    Frame := Navigation.Update(State, 1000); Check(not Frame.CanMove, 'new input waits for neutral');
    State.LeftX := 0; Frame := Navigation.Update(State, 1033); Check(Frame.CanMove, 'neutral enables subsequent movement');
    State.Buttons := 2; Frame := Navigation.Update(State, 1066); Check(Frame.Pressed(PadButtonA), 'button edge detected once');
    Frame := Navigation.Update(State, 1099); Check(not Frame.Pressed(PadButtonA), 'held button does not repeat edge');
    Frame := Navigation.Update(State, 2000); Check(SameValue(Frame.Factor, 3), 'long frame interval clamps speed');
    Navigation.Reset; State.LeftX := 1; Frame := Navigation.Update(State, 2033);
    Check(not Frame.CanMove, 'reconnect resets neutral gate');
  finally Navigation.Free; end;
end;

procedure RunPreviewTests;
var Document: TRigmDocument; Pose: TRigmPose; Preview: TRigmGamepadPreview; State: TGamepadState;
    Id: string; Revision: UInt64;
begin
  Document := TRigmDocument.Create; Pose := TRigmPose.Create; Preview := TRigmGamepadPreview.Create;
  try
    Id := Document.FileId; Revision := Document.Art.Revision;
    State := TGamepadState.Neutral; Preview.Apply(State, 1000, Document, Pose);
    State.LeftX := 0.5; State.LeftY := 0.5; State.RightX := 0.5;
    Check(Preview.Apply(State, 1033, Document, Pose) and (Pose.Value('gazeX') > 0) and
      (Pose.Value('gazeY') < 0) and (Pose.Value('headAngle') > 0), 'selected eyes and right-stick head move together');
    State.Buttons := Cardinal(1) shl (PadButtonB - 1); Preview.Apply(State, 1066, Document, Pose);
    Check(SameValue(Pose.Value('gazeX'), 0) and SameValue(Pose.Value('headAngle'), 0), 'B restores preview session before movement');
    State := TGamepadState.Neutral; Preview.Apply(State, 1099, Document, Pose);
    State.LeftX := 1; Preview.Apply(State, 1132, Document, Pose); var Before := Pose.Value('gazeX');
    State.Buttons := Cardinal(1) shl (PadButtonA - 1); Preview.Apply(State, 1165, Document, Pose);
    State.Buttons := Cardinal(1) shl (PadButtonB - 1); Preview.Apply(State, 1198, Document, Pose);
    Check(SameValue(Pose.Value('gazeX'), Before), 'A confirms preview so later B preserves it');
    State := TGamepadState.Neutral; State.POV := 18000; Preview.Apply(State, 1231, Document, Pose);
    Check(Preview.Target = gtMouth, 'direction down selects next preview target');
    State.LeftY := 1; State.POV := PadPOVNeutral; Preview.Apply(State, 1264, Document, Pose);
    Check(SameValue(Pose.Value('mouthOpen'), 0), 'target switch waits for neutral before moving new target');
    State := TGamepadState.Neutral; Preview.Apply(State, 1297, Document, Pose);
    State.LeftY := 1; Preview.Apply(State, 1330, Document, Pose);
    Check(Pose.Value('mouthOpen') > 0, 'mouth target uses left-stick vertical movement');
    State := TGamepadState.Neutral; State.Buttons := (Cardinal(1) shl (PadButtonZR - 1)) or (Cardinal(1) shl (PadButtonZL - 1));
    Preview.Apply(State, 1363, Document, Pose);
    Check(SameValue(Pose.Value('eyeOpen'), 0) and SameValue(Pose.Value('mouthOpen'), 1), 'blink and mouth can be held together');
    Preview.Release(Pose);
    Check(SameValue(Pose.Value('eyeOpen', 1), 1) and (Pose.Value('mouthOpen') < 1), 'disconnect releases temporary expressions');
    Preview.Target := gtHead; State := TGamepadState.Neutral; Preview.Apply(State, 1400, Document, Pose);
    State.LeftX := 1; for var I := 1 to 100 do Preview.Apply(State, 1400 + UInt64(I) * 33, Document, Pose);
    Check(SameValue(Pose.Value('headAngle'), 30), 'preview parameter stays within declared range');
    State.Buttons := Cardinal(1) shl (PadButtonY - 1); Preview.Apply(State, 4800, Document, Pose);
    Check(SameValue(Pose.Value('headAngle'), 0), 'Y resets selected target even with held stick');
    Check((Document.FileId = Id) and (Document.Art.Revision = Revision) and not Document.Usable, 'controller preview does not edit document or completion');
    var Input := TSwitchProInput.Create(False, False);
    try Input.Disconnect; Check(not Input.Connected and (Input.ReportCount = 0), 'input construction and disconnect do not open device'); finally Input.Free; end;
  finally Preview.Free; Pose.Free; Document.Free; end;
end;

procedure ProbeReadOnly;
var Input: TSwitchProInput; Devices: TArray<TSwitchProDeviceInfo>; Report, Device: TJSONObject;
    Items: TJSONArray; State: TGamepadState; Start: UInt64; InterfaceCount: Integer; EnumerationError: Cardinal;
begin
  Devices := TSwitchProInput.EnumerateDevices(InterfaceCount, EnumerationError); Report := TJSONObject.Create;
  Input := TSwitchProInput.Create(False, False);
  try
    AddB(Report, 'readOnly', True); AddB(Report, 'reportModeWritesEnabled', False); AddB(Report, 'playerLedWritesEnabled', False);
    AddN(Report, 'hidInterfaceCount', InterfaceCount); AddN(Report, 'enumerationError', EnumerationError);
    Items := TJSONArray.Create; Report.AddPair('devices', Items);
    for var Info in Devices do begin
      Device := TJSONObject.Create; Items.AddElement(Device); Device.AddPair('path', Info.Path);
      AddN(Device, 'inputLength', Info.InputLength); AddN(Device, 'outputLength', Info.OutputLength);
      AddN(Device, 'usage', Info.Usage); AddN(Device, 'usagePage', Info.UsagePage);
    end;
    Start := GetTickCount64;
    while GetTickCount64 - Start < 1500 do begin Input.Poll(State); Sleep(10); end;
    AddB(Report, 'connected', Input.Connected); AddN(Report, 'validReports', Input.ReportCount);
    AddN(Report, 'lastReportId', Input.LastReportId); AddB(Report, 'fullModeEnabled', Input.FullModeEnabled);
    TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)), 'controller-readonly-probe.json'), Report.ToJSON, TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally Input.Free; Report.Free; end;
end;

begin
  if (ParamCount > 0) and (ParamStr(1) = '--probe-readonly') then begin ProbeReadOnly; Exit; end;
  Checks := TJSONArray.Create;
  try
    try RunProtocolTests; RunPreviewTests; Writeln(Format('%d controller checks passed', [Count]));
    except on E: Exception do begin Writeln(E.ClassName + ': ' + E.Message); Checks.Add('FAIL: ' + E.Message); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try AddN(Report, 'passed', Count); AddB(Report, 'success', ExitCode = 0); Report.AddPair('checks', Checks); Checks := nil;
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)), 'controller-results.json'), Report.ToJSON, TEncoding.UTF8);
    finally Report.Free; end;
  finally Checks.Free; end;
end.
