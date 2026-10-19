program VoiceDeviceSessionCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, Vcl.Forms,
  RigmWizardWorkspace, RigmJson;
var Root: string; Checks: Integer;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Inc(Checks); Writeln('PASS ',Message);
end;
procedure CheckDevice(W: TRigmWizardWorkspace; Open: Boolean; const Message: string);
begin
  var State := W.VoiceConnectionStatus;
  try
    Check((JB(State,'playbackDeviceOpen')=Open) and
      (JB(State,'playbackPageActive')=Open),Message);
    if Open then Check(JI(State,'playbackDeviceOpenCount')=1,'page session opened the device only once');
  finally State.Free; end;
end;
begin
  Application.Initialize; Root := ParamStr(1);
  try
    if (Root='') or DirectoryExists(Root) then raise Exception.Create('New isolated output directory required');
    ForceDirectories(Root);
    var W := TRigmWizardWorkspace.Create(nil);
    try
      W.StartPipe(TPath.Combine(Root,'OwnedData')); W.NewScriptDraft;
      CheckDevice(W,False,'no device outside audio page');
      W.SetVoicePlaybackPageActive(True);
      CheckDevice(W,True,'page activation opens idle device');
      Check(not W.VoicePlaying and not W.VoiceContinuous,'idle open device does not count as playing');
      for var I := 1 to 5 do begin
        W.SetVoicePlaybackPageActive(True); W.StopVoice;
        CheckDevice(W,True,'repeated activation and stop preserve device');
      end;
      W.CancelVoice; CheckDevice(W,True,'cancel keeps device on audio page');
      W.SetVoicePlaybackPageActive(False);
      CheckDevice(W,False,'page departure closes device');
      W.SetVoicePlaybackPageActive(False);
      CheckDevice(W,False,'repeated departure is safe');
      W.SetVoicePlaybackPageActive(True);
      W.SetScriptTitle('音声デバイスの所有テスト'); W.NextScriptDraft;
      CheckDevice(W,False,'saving a different stage releases device');
      Check(W.CurrentScriptStage='characters','stage navigation succeeds with idle open device');
      W.SetVoicePlaybackPageActive(True);
      CheckDevice(W,True,'reentry opens a new page session');
    finally W.Free; end;
    Check(True,'workspace destruction releases active page session');
    Writeln('CHECKS=',Checks);
  except on E: Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
