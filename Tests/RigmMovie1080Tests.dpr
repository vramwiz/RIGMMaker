program RigmMovie1080Tests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Math, System.Hash,
  Winapi.Windows, Winapi.PsAPI, RigmMovieModel, RigmMovieSession, RigmStorage,
  RigmModel, RigmJson, ArtDocument;
var Session: TRigmMovieSession; Root: string; PeakPrivate,PeakWorking: UInt64;
function Call(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  try Args.AddPair('projectId',Session.Project.Id); AddN(Args,'revision',Session.Project.Revision); Result := Session.Execute(Name,Args); finally Args.Free; end;
end;
procedure Run;
var P: TRigmMovieProject; Doc: TRigmDocument; O,A: TJSONObject; Started,ReportAt,Deadline: UInt64; Cues: Integer;
begin
  Cues := StrToInt(ParamStr(4)); O := nil; var Script := '';
  for var I := 0 to Cues-1 do begin if I mod 10=0 then Script := Script+'# 場面'+(I div 10+1).ToString+sLineBreak; Script := Script+'narrator:保存済み素材、セリフ'+(I+1).ToString+'です。'+sLineBreak; end;
  P := TRigmMovieProject.FromText(Script); P.CharacterFile := ParamStr(1); P.FfmpegExe := ParamStr(2); P.EncodeProfile := ParamStr(3);
  P.Width := 1920; P.Height := 1080; P.Fps := 30;
  Doc := LoadRigm(P.CharacterFile);
  try
    var Wave := TPath.Combine(ExtractFilePath(P.CharacterFile),'EXPLICIT-TEST-TONE.wav');
    for var I := 0 to Cues-1 do begin
      var C := P.Cues[I]; C.Pause := 0.2; C.AudioSeconds := 2.8; C.WaveFile := Wave; C.AudioKey := P.AudioFingerprint(C);
      C.Motion := 'nod'; C.Acting.HeadGain := 0.6; C.Acting.BodyGain := 0.5; C.Acting.FadeIn := 0.2; C.Acting.FadeOut := 0.2;
      C.Acting.MouthMode := 'assets'; C.Acting.BlinkMode := 'assets';
      for var G in Doc.Layers do if G.Kind=alkGroup then begin
        var Choice := '';
        if G.Name='体（ポーズ）' then case (I div 10) mod 6 of 0: Choice := '*通常'; 1: Choice := '*左上を指さす'; 2: Choice := '*右上を指さす'; 3: Choice := '*手のひらで紹介'; 4: Choice := '*腕組み'; 5: Choice := '*胸に手を添える'; end;
        if G.Name='眉' then begin Choice := '*通常'; if I mod 3=1 then Choice := '*楽'; if I mod 3=2 then Choice := '*困る'; end;
        if Choice<>'' then for var L in G.Children do if L.Name=Choice then begin
          A := TJSONObject.Create; A.AddPair('groupId',G.Id); A.AddPair('partId',L.Id); C.Acting.Variants.AddElement(A);
        end;
      end;
    end;
    SaveMovie(P,TPath.Combine(Root,'fullhd.rigmovie')); Session.SetProject(P); P := nil;
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'fullhd-tone.mp4')); O := Call('export',A); O.Free; O := nil;
    Started := GetTickCount64; ReportAt := 0; Deadline := Started+1800000;
    repeat
      Session.Poll; O := Call('job-status');
      var Counters := Default(TProcessMemoryCountersEx); Counters.cb := SizeOf(Counters);
      if GetProcessMemoryInfo(GetCurrentProcess,@Counters,SizeOf(Counters)) then begin PeakPrivate := Max(PeakPrivate,Counters.PrivateUsage); PeakWorking := Max(PeakWorking,Counters.WorkingSetSize); end;
      if GetTickCount64>=ReportAt then begin Writeln('PROGRESS ',JS(O,'phase'),' ',JN(O,'phaseCompleted'):0:1,'/',JN(O,'phaseTotal'):0:1,' elapsed=',JN(O,'elapsedSeconds'):0:1,' remain=',JN(O,'remainingSeconds'):0:1); ReportAt := GetTickCount64+2000; end;
      if JB(O,'done') then Break;
      O.Free; O := nil; Sleep(10);
      if FileExists(TPath.Combine(Root,'cancel.txt')) then begin var Reply := Call('job-cancel'); Reply.Free; end;
    until GetTickCount64>Deadline;
    if (O=nil) or (JS(O,'state')<>'succeeded') then raise Exception.Create('1080 export failed '+O.ToJSON);
    var Result := TJSONObject.Create;
    try AddB(Result,'success',True); Result.AddPair('directory',Root); AddN(Result,'duration',Cues*3); AddN(Result,'frames',Cues*90); AddN(Result,'width',1920); AddN(Result,'height',1080); AddN(Result,'fps',30);
      Result.AddPair('encodeProfile',ParamStr(3)); AddN(Result,'exportWallMs',GetTickCount64-Started); AddN(Result,'videoBytes',TFile.GetSize(TPath.Combine(Root,'fullhd-tone.mp4')));
      AddN(Result,'appPeakPrivateBytes',PeakPrivate); AddN(Result,'appPeakWorkingSetBytes',PeakWorking); Result.AddPair('job',O.Clone as TJSONObject);
      Result.AddPair('audioSource','explicit test tone; no real speech'); Result.AddPair('material','independent copy of stored Kiritan, 44 layers, prepared 6 bones/5x5 meshes');
      TFile.WriteAllText(TPath.Combine(Root,'results.json'),Result.ToJSON,TEncoding.UTF8);
      TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'movie-1080-latest.json'),Result.ToJSON,TEncoding.UTF8);
    finally Result.Free; end;
  finally O.Free; Doc.Free; P.Free; end;
end;
begin
  Root := TPath.Combine(ExtractFilePath(ParamStr(0)),'Movie1080\'+FormatDateTime('yyyymmdd-hhnnss-zzz',Now)); ForceDirectories(Root); Session := TRigmMovieSession.Create;
  try try Run; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end; finally Session.Free; end;
end.
