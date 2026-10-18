program SummarySubtitleCheck;
{$APPTYPE CONSOLE}
// 実作品は読み取りだけに使い、旧字幕ずれの補正・個別編集保護・合成画素を検証する。
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash, System.Math, System.Generics.Collections,
  Winapi.Windows, Vcl.Forms, Vcl.Graphics, Vcl.Imaging.pngimage,
  RigmMovieModel, RigmScriptSummaryFields, RigmScriptSummaryModel,
  RigmMovieRendering, RigmMovieCompositor, RigmMovieWorkflow, RigmJson, PsdJson;
var Checks: TJSONArray; Output,Error: string;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Checks.Add(Message); Writeln('PASS ',Message);
end;
function RawProject(const Path: string): TRigmMovieProject;
begin
  var O := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
  try Result := TRigmMovieProject.FromJson(O); Result.FileName := Path; finally O.Free; end;
end;
function WithoutSubtitle(C: TRigmMovieCue): string;
begin
  var O := C.Json;
  try O.RemovePair('subtitle').Free; Result := O.ToJSON; finally O.Free; end;
end;
procedure Run;
begin
  var Path := ParamStr(1); Output := ParamStr(2); ForceDirectories(Output);
  var Hash := THashSHA2.GetHashStringFromFile(Path); var Raw := RawProject(Path);
  try
    var O := JO(Raw.ScriptWizard,'summaryData'); var Ids := JA(O,'cueIds');
    var Broken := 0;
    for var Id in Ids do if Raw.Cue(Id.Value).Subtitle='' then Inc(Broken);
    Check(Broken>0,'saved reproduction contains missing summary subtitles');
    var Fixed := Raw.Clone;
    try
      Check(RestoreScriptSummarySubtitles(Fixed),'exact old blank-line mapping is repaired');
      Check(not RestoreScriptSummarySubtitles(Fixed),'repair is idempotent');
      Check(MovieRenderKey(Fixed)<>MovieRenderKey(Raw),'subtitle repair invalidates old preview and video cache');
      for var C in Fixed.Cues do begin
        Check(WithoutSubtitle(C)=WithoutSubtitle(Raw.Cue(C.Id)),
          'cue audio, reading, IDs and acting remain unchanged '+C.Id);
        Check(Fixed.AudioFingerprint(C)=Raw.AudioFingerprint(Raw.Cue(C.Id)),
          'subtitle repair preserves audio fingerprint '+C.Id);
        if C.Scene=JS(O,'sceneId') then
          Check(C.Subtitle=C.Text,'each repaired summary subtitle matches its spoken source '+C.Id)
        else Check(C.Subtitle=Raw.Cue(C.Id).Subtitle,'ordinary subtitle remains unchanged '+C.Id);
      end;
      Check(Fixed.Scenes.Count=Raw.Scenes.Count,'scene count remains unchanged');
      var Saved := TPath.Combine(Output,'repaired.rigmovie'); SaveMovie(Fixed,Saved);
      var Reloaded := LoadMovie(Saved);
      try
        for var Id in Ids do Check(Reloaded.Cue(Id.Value).Subtitle=Fixed.Cue(Id.Value).Subtitle,
          'repaired subtitle survives owned save and reload '+Id.Value);
      finally Reloaded.Free; end;
      Fixed.Width := 960; Fixed.Height := 540;
      var Index := 0;
      for var Id in Ids do begin
        Inc(Index); var C := Fixed.Cue(Id.Value); var Empty := Fixed.Clone;
        try
          Empty.Cue(C.Id).Subtitle := '';
          var Time := Fixed.CueStart(C)+Min(0.05,Fixed.CueDuration(C)/2);
          var Visible := RenderComposition(Fixed,Time,nil);
          try
            var Hidden := RenderComposition(Empty,Time,nil);
            try
              GdiFlush; var Area := MovieSubtitleContentRect(Fixed); var Changed := 0;
              for var Y := Area.Top to Area.Bottom-1 do begin
                var A := PByte(Visible.ScanLine[Y]); var B := PByte(Hidden.ScanLine[Y]);
                for var X := Area.Left*4 to Area.Right*4-1 do if A[X]<>B[X] then Inc(Changed);
              end;
              Check(Changed>100,'summary frame contains visible subtitle pixels '+Index.ToString);
              var PNG := TPngImage.Create;
              try PNG.Assign(Visible); PNG.SaveToFile(TPath.Combine(Output,'summary-'+Index.ToString+'.png')); finally PNG.Free; end;
            finally Hidden.Free; end;
          finally Visible.Free; end;
        finally Empty.Free; end;
      end;
    finally Fixed.Free; end;
    Fixed := LoadMovie(Path);
    try
      for var Id in Ids do Check(Fixed.Cue(Id.Value).Subtitle=Fixed.Cue(Id.Value).Text,
        'normal project load repairs summary subtitles '+Id.Value);
    finally Fixed.Free; end;
    for var Value in ['個別の字幕',''] do begin
      Fixed := Raw.Clone;
      try
        Fixed.Cue(Ids[0].Value).Subtitle := Value;
        var Before := Fixed.Json;
        try Check(not RestoreScriptSummarySubtitles(Fixed),'individual edit or hidden subtitle prevents inferred repair');
          var After := Fixed.Json;
          try Check(Before.ToJSON=After.ToJSON,'edited summary remains byte-for-byte unchanged'); finally After.Free; end;
        finally Before.Free; end;
      finally Fixed.Free; end;
    end;
    var Draft := PsdJson.ObjectText('{"text":"一行目\r\n\r\n二行目\r\n\r\n三行目","subtitle":"","reading":""}');
    try
      for var Key in ['subtitle','reading'] do begin
        PsdJson.Put(Draft,Key,JS(Draft,'text'));
        Check(ScriptSummaryFieldLine(Draft,Key,1,3,'二行目')='二行目','source paragraphs align '+Key);
        PsdJson.Put(Draft,Key,'独立1'+#13#10+#13#10+'独立2'+#13#10+#13#10+'独立3');
        Check(ScriptSummaryFieldLine(Draft,Key,1,3,'二行目')='独立2','independent paragraphs align '+Key);
      end;
      PsdJson.Put(Draft,'subtitle','字幕1'+#13#10+#13#10+'字幕3');
      Check(ScriptSummaryFieldLine(Draft,'subtitle',1,3,'二行目')='','explicit empty subtitle row stays hidden');
      PsdJson.Put(Draft,'subtitle','一続きの字幕');
      Check((ScriptSummaryFieldLine(Draft,'subtitle',0,3,'一行目')='一続きの字幕') and
        (ScriptSummaryFieldLine(Draft,'subtitle',1,3,'二行目')=''),'single independent subtitle stays on first cue');
    finally Draft.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Path)=Hash,'original project SHA256 remains unchanged');
  finally Raw.Free; end;
end;
begin
  Application.Initialize; Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
    if Output<>'' then begin
      var Report := TJSONObject.Create.AddPair('error',Error).AddPair('checks',Checks.Clone as TJSONArray);
      try TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end;
    end;
  finally Checks.Free; end;
end.
