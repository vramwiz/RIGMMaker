program SummaryReadingCheck;
{$APPTYPE CONSOLE}
// 旧総評の読みずれを検証し、-apply指定時だけバックアップ済み実台本へ補正・音声再生成を保存する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections, Winapi.Windows, Winapi.TlHelp32, Vcl.Forms,
  RigmMovieModel, RigmScriptSummaryFields, RigmScriptSummaryModel,
  RigmScriptCastingModel, RigmMovieJobs, RigmMovieAudio, PsdJson, RigmJson;
var Output,Error: string; Checks: TJSONArray;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); Writeln('PASS ',Message); end;
function RawProject(const Path: string): TRigmMovieProject;
begin
  var O := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
  try Result := TRigmMovieProject.FromJson(O); Result.FileName := Path; finally O.Free; end;
end;
procedure RequireAppClosed;
begin
  var Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
  if Snapshot=INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    var Entry := Default(TProcessEntry32); Entry.dwSize := SizeOf(Entry);
    if Process32First(Snapshot,Entry) then repeat
      if LowerCase(string(Entry.szExeFile)).StartsWith('rigmmaker') then
        raise Exception.Create('Application is running; preserve its live data and use the pipe.');
    until not Process32Next(Snapshot,Entry);
  finally CloseHandle(Snapshot); end;
end;
procedure Run;
begin
  var Path := ParamStr(1); Output := ParamStr(2); ForceDirectories(Output);
  var Hash := THashSHA2.GetHashStringFromFile(Path);
  var Raw := RawProject(Path); var Fixed := Raw.Clone;
  try
    Check(RestoreScriptSummaryReadings(Fixed),'legacy reading signature is repaired after source-line insertion');
    var Migration := JA(JO(Fixed.ScriptWizard,'summaryData'),'readingLineMigration');
    Check(Migration.Count=4,'exactly four wrong reading overrides are repaired');
    Check(Fixed.Cues.Count=Raw.Cues.Count,'all 63 source cues remain, including added lines');
    for var Before in Raw.Cues do begin
      var After := Fixed.Cue(Before.Id); var BeforeJson := Before.Json; var Expected: TRigmMovieCue;
      try Expected := TRigmMovieCue.FromJson(BeforeJson); finally BeforeJson.Free; end;
      try
        var Affected := False;
        for var V in Migration do if JS(TJSONObject(V),'id')=Before.Id then begin
          Affected := True;
          var Original := Before.Json;
          try Check(Original.ToJSON=V.ToJSON,'previous audio and reading are archived '+Before.Id); finally Original.Free; end;
        end;
        if Affected then begin
          Expected.VoiceReading := ''; Expected.VoiceQuery := ''; Expected.VoiceQueryKey := '';
          Expected.AudioKey := ''; Expected.VoiceHeardKey := ''; Expected.EffectAudioKey := '';
          Check((After.SpokenText=After.Text) and not Fixed.AudioReady(After),
            'wrong reading uses its own source and requires fresh audio '+Before.Id);
        end;
        var A := After.Json; var B := Expected.Json;
        try Check(A.ToJSON=B.ToJSON,'source, subtitle and unaffected cue adjustments stay intact '+Before.Id); finally B.Free; A.Free; end;
      finally Expected.Free; end;
    end;
    var SourceJson := Raw.Json; var FixedJson := Fixed.Json;
    try
      for var Key in ['scenes','characters','scriptWizard','cues'] do begin
        if (Key='scenes') or (Key='characters') then
          Check(SourceJson.GetValue(Key).ToJSON=FixedJson.GetValue(Key).ToJSON,Key+' are unchanged');
      end;
    finally FixedJson.Free; SourceJson.Free; end;
    Check(not RestoreScriptSummaryReadings(Fixed),'reading migration is idempotent');
    var Recast := Fixed.Clone;
    try
      PrepareScriptCasting(Recast);
      for var C in Fixed.Cues do begin
        var A := C.Json; var B := Recast.Cue(C.Id).Json;
        try Check(A.ToJSON=B.ToJSON,'recasting preserves corrected reading and all other adjustments '+C.Id); finally B.Free; A.Free; end;
      end;
    finally Recast.Free; end;
    var Edited := Raw.Clone;
    try
      Edited.Cue(JS(TJSONObject(Migration[0]),'id')).VoiceReading := '人間が指定した独自の読み';
      var Before := Edited.Json;
      try Check(not RestoreScriptSummaryReadings(Edited),'custom reading prevents inferred correction');
        var After := Edited.Json;
        try Check(Before.ToJSON=After.ToJSON,'custom reading and all data are preserved'); finally After.Free; end;
      finally Before.Free; end;
    finally Edited.Free; end;
    var Loaded := LoadMovie(Path);
    try
      for var C in Fixed.Cues do Check(Loaded.Cue(C.Id).SpokenText=C.SpokenText,'ordinary load restores each expected reading '+C.Id);
    finally Loaded.Free; end;
    var Saved := TPath.Combine(Output,'corrected.rigmovie'); var Copy := Fixed.Clone;
    try SaveMovie(Copy,Saved); var Reloaded := LoadMovie(Saved);
      try for var C in Copy.Cues do Check(Reloaded.Cue(C.Id).SpokenText=C.SpokenText,'reading correction survives save and reload '+C.Id);
      finally Reloaded.Free; end;
    finally Copy.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Path)=Hash,'validation preserves original project SHA256');
    if FindCmdLineSwitch('apply') then begin
      RequireAppClosed;
      Check(SameText(Hash,ParamStr(3)),'apply uses the expected backed-up source SHA256');
      var Generated := TJSONArray.Create;
      try
        for var V in Migration do begin
          var Id := JS(TJSONObject(V),'id'); var Options := TJSONObject.Create
            .AddPair('cueId',Id).AddPair('captureQuery',TJSONBool.Create(True));
          var Job: TRigmMovieJob;
          try Job := TRigmMovieJob.Create(Fixed,'audio',TPath.Combine(ExtractFileDir(Path),'Audio'),0,Options); finally Options.Free; end;
          try
            Job.Start; var Deadline := GetTickCount64+120000;
            repeat Application.ProcessMessages; Sleep(10); if GetTickCount64>Deadline then begin Job.Cancel; raise Exception.Create('Owned audio generation timeout'); end; until Job.Done;
            Job.WaitFor; var Status := Job.Status;
            try Check(JS(Status,'state')='succeeded','corrected cue synthesis succeeds '+Id+': '+JS(Status,'error')); finally Status.Free; end;
            var Source := Job.Project.Cue(Id); var Target := Fixed.Cue(Id);
            Target.VoiceQuery := Source.VoiceQuery; Target.VoiceQueryKey := Source.VoiceQueryKey;
            Target.WaveFile := Source.WaveFile; Target.LabFile := Source.LabFile;
            Target.AudioSeconds := Source.AudioSeconds; Target.AudioKey := Source.AudioKey;
            Check(Fixed.AudioReady(Target) and not Fixed.AudioHeard(Target),'new audio is current and still needs human playback '+Id);
            var Pcm := TRigmPcm.Load(Target.WaveFile);
            try Check((Pcm.Duration>0) and (Abs(Pcm.Duration-Target.AudioSeconds)<0.002),'generated WAV duration is valid '+Id); finally Pcm.Free; end;
            Generated.AddElement(Target.Json);
          finally Job.Free; end;
        end;
        TFile.WriteAllText(TPath.Combine(Output,'generated.json'),Generated.ToJSON,TEncoding.UTF8);
      finally Generated.Free; end;
      RequireAppClosed;
      Check(THashSHA2.GetHashStringFromFile(Path)=Hash,'source has not changed before atomic save');
      Fixed.Changed; SaveMovie(Fixed,Path);
      var Reloaded := LoadMovie(Path);
      try
        Check(Reloaded.Cues.Count=Raw.Cues.Count,'saved repair keeps every original cue');
        for var C in Reloaded.Cues do Check(C.SpokenText=C.Text,'saved cue has one correct source reading '+C.Id);
      finally Reloaded.Free; end;
    end;
  finally Fixed.Free; Raw.Free; end;
end;
begin
  Application.Initialize; Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
    if Output<>'' then begin
      var Report := TJSONObject.Create.AddPair('checks',Checks.Clone as TJSONArray).AddPair('error',Error);
      try TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end;
    end;
  finally Checks.Free; end;
end.
