program PsdRegister;
{$APPTYPE CONSOLE}

// アプリの共通セッションを使ったローカル素材登録。元素材は読取りだけ。
uses System.SysUtils, System.IOUtils, System.JSON, Winapi.Windows,
  PsdSession, PsdWorkspace, PsdJson, PsdCharacter, PsdPackage, ArtDocument,
  ArtPng, ArtPsd, PsdAnimation;
begin
  try
    if (ParamCount <> 3) and (ParamCount <> 4) then raise Exception.Create('Usage: PsdRegister <data-root> <manifest-relative-path> <character-stem> [--refresh]');
    var Session := TPsdSession.Create(ParamStr(1), False);
    try
      var Status := Session.Status; var A := TJSONObject.Create;
      try A.AddPair('sessionId', S(Status, 'sessionId')); A.AddPair('revision', S(Status, 'revision')); A.AddPair('path', ParamStr(2));
      finally Status.Free; end;
      try var R := Session.Command('import-prepared', A); R.Free; finally A.Free; end;
      var Character := Session.Character;
      var Path := 'Characters\' + ParamStr(3) + '.psdchar';
      if FileExists(Session.Workspace.Resolve(Path, False)) then begin
        if (ParamCount <> 4) or (ParamStr(4) <> '--refresh') then raise Exception.Create('Existing registration is preserved; use a new stem or explicit --refresh');
        var Old := LoadCharacter(Session.Workspace, Path);
        try
          if (Old.Policy <> 'managed') or (Old.Source <> Character.Source) then raise Exception.Create('Refresh source/policy mismatch');
          Character.Id := Old.Id;
        finally Old.Free; end;
      end;
      SaveCharacter(Character, Session.Workspace, Path);
      if not FileExists(Session.Workspace.Resolve('Characters\' + ParamStr(3) + '.psd', False)) then
        ExportPsd(Character, Session.Workspace, 'Characters\' + ParamStr(3) + '.psd');
      var Renderer := TPsdRenderer.Create(Character, Session.Workspace, 0);
      try
        var State := TPsdFrameState.Default; State.Motion := 'none'; State.AutoBlink := False;
        var Neutral := Renderer.Composite(State);
        WriteRgbaPng(Session.Workspace.Resolve('Characters\' + ParamStr(3) + '-neutral.png', False), Character.Document.Width, Character.Document.Height, Neutral);
        var Loaded := LoadCharacter(Session.Workspace, Path); var Again := TPsdRenderer.Create(Loaded, Session.Workspace, 0);
        try
          var Data := Again.Composite(State);
          if (Length(Data) <> Length(Neutral)) or not CompareMem(@Data[0], @Neutral[0], Length(Data)) then raise Exception.Create('Roundtrip composite differs');
          var Count := 0;
          for var V in Arr(Character.Settings, 'groups') do for var P in Arr(TJSONObject(V), 'partIds') do begin
            var Original := Character.Document.FindLayer(P.Value); var Saved := Loaded.Document.FindLayer(P.Value);
            if (Saved = nil) or (Length(Original.Pixels) <> Length(Saved.Pixels)) or not CompareMem(@Original.Pixels[0], @Saved.Pixels[0], Length(Original.Pixels)) then
              raise Exception.Create('Layer RGBA differs after save'); Inc(Count);
          end;
          Writeln('Verified layers: ', Count, '; neutral RGBA identical; source retained');
        finally Again.Free; Loaded.Free; end;
      finally Renderer.Free; end;
      Writeln('Character: ', Character.Name); Writeln('Package: ', Session.Workspace.Resolve(Path));
      Writeln('PSD: ', Session.Workspace.Resolve('Characters\' + ParamStr(3) + '.psd'));
    finally Session.Free; end;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
