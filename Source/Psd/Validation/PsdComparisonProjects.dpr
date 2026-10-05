program PsdComparisonProjects;
{$APPTYPE CONSOLE}

// 検証済みの共通作品から、無音で編集可能な実キャラ比較作品を別名で保存する。
uses System.SysUtils, System.IOUtils, System.JSON, Vcl.Forms, Vcl.Graphics,
  Vcl.Imaging.pngimage, RigmJson, RigmMovieModel, RigmMovieCompositionCommands,
  RigmMovieCompositor, RigmMovieRendering, RigmCharacterCatalog, RigmStorage;

procedure CreateExample(const Source,Target: string);
begin
  if FileExists(Target) then raise Exception.Create('New comparison filename required');
  var Project := LoadMovie(Source);
  try
    var Actor := Project.Characters[0]; var IsPsd := Actor.RenderFormat='psd';
    Project.Cues.Clear;
    var Args := TJSONObject.Create;
    try ApplyCompositionCommand(Project,'analyze-script',Args); finally Args.Free; end;
    if IsPsd then begin
      var Asset := TPsdCharacterAsset.Create(ResolveMoviePath(Project.FileName,Actor.FileName));
      try Actor.Name := Asset.Character.Name; finally Asset.Free; end;
      Actor.PsdView.Free; Actor.PsdView := ParseObject('{"gaze":"front","motion":"breathe","autoBlink":true}');
      Project.Title := '金髪アンドロイド・PSD比較（無音8秒）';
    end else begin
      var Document := LoadRigm(ResolveMoviePath(Project.FileName,Actor.FileName));
      try Actor.Name := Document.Name; finally Document.Free; end;
      Project.Title := '金髪アンドロイド・Live2D風比較（無音8秒）';
    end;
    for var Emotion in ['neutral','happy','sad','serious'] do begin
      var Cue := TRigmMovieCue.Create; Cue.Pause := 2; Cue.SpeakerId := Actor.SpeakerId;
      Cue.Emotion := Emotion; Cue.Text := ''; Cue.Motion := 'idle';
      if Emotion='neutral' then Cue.Subtitle := '通常：共通動画画面で表示'
      else if Emotion='happy' then Cue.Subtitle := '喜び：保存済み表情差分'
      else if Emotion='sad' then Cue.Subtitle := '哀しみ：既存差分の組み合わせ'
      else Cue.Subtitle := '解説：呼吸や小さな動きを併用';
      Project.Cues.Add(Cue);
    end;
    SaveMovie(Project,Target,True);
    var Loaded := LoadMovie(Target);
    try
      Loaded.Validate; ValidateCompositionMaterials(Loaded);
      if (Loaded.Duration<>8) or (Loaded.Characters[0].RenderFormat<>Actor.RenderFormat) then
        raise Exception.Create('Comparison roundtrip failed');
      var Frame := RenderMovieFrame(Loaded,nil,0.5); var Image := TPngImage.Create;
      try Image.Assign(Frame); Image.SaveToFile(TPath.Combine(ExtractFileDir(Target),'比較プレビュー.png'));
      finally Image.Free; Frame.Free; end;
      Writeln('PASS: '+Target+'; format='+Actor.RenderFormat+'; real character='+Actor.Name+'; duration=8; speech=none');
    finally Loaded.Free; end;
  finally Project.Free; end;
end;
begin
  try
    Application.Initialize;
    CreateExample(ParamStr(1),ParamStr(2));
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
