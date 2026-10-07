program EffectsPlaybackProbe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math, System.Generics.Collections,
  Winapi.Windows, Winapi.MMSystem,
  RigmEffectsPlayback;

var
  Report: TJSONObject;
  Checks, MciCases: TJSONArray;
  Failures: Integer;

procedure Check(const Name: string; Passed: Boolean; const Detail: string = '');
var Entry: TJSONObject;
begin
  Entry := TJSONObject.Create;
  Entry.AddPair('name', Name);
  Entry.AddPair('passed', TJSONBool.Create(Passed));
  Entry.AddPair('detail', Detail);
  Checks.AddElement(Entry);
  if not Passed then Inc(Failures);
end;

procedure MciBaseline(const Path: string; Index: Integer);
var Code, CloseCode: MCIERROR; AliasName, Command: string;
  TextBuffer: array[0..511] of WideChar; Entry: TJSONObject;
begin
  AliasName := 'rigm_isolated_mci_' + UIntToStr(GetCurrentProcessId) + '_' + IntToStr(Index);
  Command := 'open "' + Path + '" type waveaudio alias ' + AliasName;
  Code := mciSendStringW(PWideChar(Command), nil, 0, 0);
  FillChar(TextBuffer, SizeOf(TextBuffer), 0);
  if Code <> 0 then mciGetErrorStringW(Code, @TextBuffer[0], Length(TextBuffer));
  Entry := TJSONObject.Create;
  Entry.AddPair('path', Path); Entry.AddPair('pathLength', TJSONNumber.Create(Length(Path)));
  Entry.AddPair('stage', 'open'); Entry.AddPair('code', TJSONNumber.Create(Code));
  Entry.AddPair('text', string(PWideChar(@TextBuffer[0])));
  CloseCode := 0;
  if Code = 0 then
    CloseCode := mciSendStringW(PWideChar('close ' + AliasName), nil, 0, 0);
  Entry.AddPair('closeCode', TJSONNumber.Create(CloseCode));
  MciCases.AddElement(Entry);
end;

procedure ExercisePath(const Path: string; Index: Integer; Seconds: Double);
var Player: TRigmEffectsPlayback; Started: UInt64; Position: Double; Prefix: string;
begin
  Prefix := 'path' + IntToStr(Index) + '.';
  Player := TRigmEffectsPlayback.Create;
  try
    try
      Player.Open(Path);
      Check(Prefix + 'open', Player.Loaded and Player.IsOpen and (Player.Path = Path));
      Check(Prefix + 'duration', Abs(Player.DurationSeconds - Seconds) < 0.00001,
        FloatToStr(Player.DurationSeconds, TFormatSettings.Invariant));
      Check(Prefix + 'initial', not Player.Playing and (Player.PositionSeconds = 0));
      Player.Play;
      Sleep(180);
      Position := Player.PositionSeconds;
      Check(Prefix + 'playing', Player.Playing);
      Check(Prefix + 'progress', (Position > 0.02) and (Position <= Player.DurationSeconds),
        FloatToStr(Position, TFormatSettings.Invariant));
      Player.Stop;
      Check(Prefix + 'stop', not Player.Playing and (Player.PositionSeconds = 0) and Player.Loaded);
      Player.Stop;
      Check(Prefix + 'repeatedStop', not Player.Playing);
      Player.Play;
      Started := GetTickCount64;
      while Player.Playing and (GetTickCount64 - Started < 5000) do Sleep(10);
      Check(Prefix + 'naturalEnd', not Player.Playing and
        (Abs(Player.PositionSeconds - Player.DurationSeconds) < 0.00001));
      for var LoopIndex := 1 to 3 do
      begin
        Player.Play; Sleep(60); Player.Stop;
        Check(Prefix + 'replay' + IntToStr(LoopIndex), not Player.Playing and (Player.PositionSeconds = 0));
      end;
      Player.Close;
      Check(Prefix + 'close', not Player.Loaded and not Player.Playing and
        (Player.DurationSeconds = 0) and (Player.PositionSeconds = 0) and (Player.Path = ''));
    except
      on E: Exception do Check(Prefix + 'exception', False, E.ClassName + ': ' + E.Message);
    end;
  finally Player.Free; end;
end;

procedure ExerciseInvalid(Manifest: TJSONObject; const GoodPath: string);
var Player: TRigmEffectsPlayback; InvalidCases: TJSONArray; ErrorRaised, Kept: Boolean;
  ErrorText, CasePath: string;
begin
  Player := TRigmEffectsPlayback.Create;
  try
    Player.Open(GoodPath);
    InvalidCases := Manifest.GetValue<TJSONArray>('invalid');
    for var I := 0 to InvalidCases.Count - 1 do
    begin
      CasePath := InvalidCases.Items[I].GetValue<string>('path');
      ErrorRaised := False; ErrorText := '';
      try Player.Open(CasePath);
      except on E: Exception do begin ErrorRaised := True; ErrorText := E.Message; end; end;
      Kept := Player.Loaded and (Player.Path = GoodPath) and (Player.DurationSeconds > 0);
      Check('invalid.' + InvalidCases.Items[I].GetValue<string>('name'),
        ErrorRaised and Kept and (Player.LastError <> ''), ErrorText);
    end;
    Player.Play; Sleep(60); Player.Stop;
    Check('invalid.recoveryPlay', Player.Loaded and not Player.Playing);
  finally Player.Free; end;
end;

procedure ExerciseLifetime(const GoodPath: string);
var Player: TRigmEffectsPlayback; OtherThread: TThread; Refused: Boolean;
begin
  for var I := 1 to 20 do
  begin
    Player := TRigmEffectsPlayback.Create;
    try Player.Open(GoodPath); Player.Play; Sleep(5); finally Player.Free; end;
  end;
  Check('lifetime.activeDestruction20', True);
  Player := TRigmEffectsPlayback.Create;
  try
    Player.Open(GoodPath);
    for var I := 1 to 10 do
    begin
      Player.Play; Sleep(5); Player.Open(GoodPath); Player.Close; Player.Open(GoodPath);
    end;
    Check('lifetime.reopen10', Player.Loaded and not Player.Playing);
    Refused := False;
    OtherThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try Player.Play;
        except on E: ERigmEffectsPlayback do Refused := True; end;
      end);
    OtherThread.FreeOnTerminate := False;
    try OtherThread.Start; OtherThread.WaitFor; finally OtherThread.Free; end;
    Check('lifetime.foreignThreadRefused', Refused and not Player.Playing);
  finally Player.Free; end;
end;

var Manifest: TJSONObject; Paths: TJSONArray; ReportPath: string;
begin
  Failures := 0;
  Report := TJSONObject.Create;
  Checks := TJSONArray.Create; MciCases := TJSONArray.Create;
  Report.AddPair('checks', Checks); Report.AddPair('mciBaseline', MciCases);
  Report.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
  {$IFDEF WIN64}Report.AddPair('architecture', 'win64');{$ELSE}Report.AddPair('architecture', 'win32');{$ENDIF}
  Manifest := nil;
  ReportPath := ParamStr(2);
  try
    try
      if ParamCount <> 2 then raise Exception.Create('Expected fixture manifest and report path.');
      Manifest := TJSONObject.ParseJSONValue(TFile.ReadAllText(ParamStr(1), TEncoding.UTF8)) as TJSONObject;
      if Manifest = nil then raise Exception.Create('Invalid fixture manifest.');
      Paths := Manifest.GetValue<TJSONArray>('valid');
      for var I := 0 to Paths.Count - 1 do
      begin
        var Path := Paths.Items[I].GetValue<string>('path');
        MciBaseline(Path, I);
        ExercisePath(Path, I, Paths.Items[I].GetValue<Double>('duration'));
      end;
      ExerciseInvalid(Manifest, Paths.Items[0].GetValue<string>('path'));
      ExerciseLifetime(Paths.Items[0].GetValue<string>('path'));
    except on E: Exception do Check('fatal', False, E.ClassName + ': ' + E.Message); end;
    Report.AddPair('failures', TJSONNumber.Create(Failures));
    TFile.WriteAllText(ReportPath, Report.ToJSON, TEncoding.UTF8);
    Writeln('Playback probe: ', Checks.Count, ' checks; ', Failures, ' failures.');
  finally Manifest.Free; Report.Free; end;
  ExitCode := Ord(Failures <> 0);
end.
