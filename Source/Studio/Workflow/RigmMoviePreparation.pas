// 素材・音声・出力設定の診断と準備結果を組み立てる。実行ジョブと画面表示から独立した判定を担当する。
unit RigmMoviePreparation;
interface
uses System.JSON, RigmMovieModel, RigmModel;
function MoviePreparationKey(Project: TRigmMovieProject): string;
function MovieCapabilities(Document: TRigmDocument): TJSONObject;
function MoviePreparation(Project: TRigmMovieProject; Diagnostics,DiagnosticJob: TJSONObject;
  const OutputPath: string=''; PreviewCurrent: Boolean=False): TJSONObject;
function MovieExamples: TJSONArray;
implementation
uses System.SysUtils, System.IOUtils, System.Math, System.StrUtils, Winapi.Windows,
  RigmJson, ArtDocument;

function MoviePreparationKey(Project: TRigmMovieProject): string;
begin
  Result := Project.EngineUrl+'|'+ResolveMoviePath(Project.FileName,Project.CharacterFile);
  for var Character in Project.Characters do begin
    Result := Result+'|'+Character.RenderFormat+'|'+Character.FileName+'|'+Character.PsdView.ToJSON+'|'+Character.Expressions.ToJSON+'|'+Character.Motions.ToJSON;
    var Path := ResolveMoviePath(Project.FileName,Character.FileName);
    if FileExists(Path) then Result := Result+'|'+TFile.GetSize(Path).ToString+'|'+DateTimeToStr(TFile.GetLastWriteTimeUtc(Path));
  end;
  var BgmPath := ResolveMoviePath(Project.FileName,Project.BgmFile); Result := Result+'|bgm|'+BgmPath;
  if BgmPath<>'' then begin
    try
      if FileExists(BgmPath) then Result := Result+'|'+TFile.GetSize(BgmPath).ToString+'|'+FormatDateTime('yyyymmddhhnnsszzz',TFile.GetLastWriteTimeUtc(BgmPath))
      else Result := Result+'|missing';
    except Result := Result+'|unreadable'; end;
  end;
  Result := Result+'|'+Project.ThemeBackground;
  for var Scene in Project.Scenes do Result := Result+'|'+Scene.DisplayMode+'|'+Scene.Image;
  for var C in Project.Cues do Result := Result+'|'+C.Id+'|'+C.Acting.MouthMode+'|'+C.Acting.BlinkMode+'|'+C.Acting.Variants.ToJSON;
  if (Project.CharacterFile<>'') and (Project.CharacterFile<>'@sample') then
    try var P := ResolveMoviePath(Project.FileName,Project.CharacterFile);
      if FileExists(P) then Result := Result+'|'+TFile.GetSize(P).ToString+'|'+DateTimeToStr(TFile.GetLastWriteTimeUtc(P));
    except Result := Result+'|unreadable'; end;
end;
function MovieCapabilities(Document: TRigmDocument): TJSONObject;
begin
  Result := TJSONObject.Create; AddB(Result,'naturalFaceDirections',False);
  var Mouth := False; var Eyes := False; var PoseGroups := 0; var ImageCount := 0;
  if Document<>nil then begin
    for var G in Document.Layers do begin
      if (G.Kind=alkImage) and not Document.IsReferencePart(G.Id) then Inc(ImageCount);
      if (G.Kind<>alkGroup) or (G.Children.Count<2) then Continue;
      var Role := Document.Part(G.Children[0].Id).Role; var Compatible := True; var Closed := False; var Open := False;
      for var L in G.Children do begin
        Compatible := Compatible and (L.Kind=alkImage) and (Document.Part(L.Id).Role=Role) and not Document.IsReferencePart(L.Id);
        var Name := L.Name.Trim.TrimLeft(['*']);
        Closed := Closed or MatchText(Name,['閉じ','closed','blink','ん']);
        Open := Open or MatchText(Name,['通常','normal','default','開き','あ','open','a']);
      end;
      if Compatible and Closed and Open then begin
        if Role='mouth' then Mouth := True; if Role='eye' then Eyes := True;
      end;
      if Compatible and (Role='body') then Inc(PoseGroups);
    end;
    AddN(Result,'bones',Document.Bones.Count); AddN(Result,'meshes',Document.Meshes.Count);
    AddB(Result,'headBodyMotion',(Document.Bones.Count>0) and (Document.Meshes.Count>0));
  end else begin AddN(Result,'bones',0); AddN(Result,'meshes',0); AddB(Result,'headBodyMotion',False); end;
  AddN(Result,'drawableImages',ImageCount); AddN(Result,'poseGroups',PoseGroups);
  AddB(Result,'mouthAssets',Mouth); AddB(Result,'blinkAssets',Eyes);
  Result.AddPair('safeMouthMode','auto'); Result.AddPair('safeBlinkMode','auto');
  Result.AddPair('faceDirectionReason','自然な左右向きの素材を推定・生成しません。保存済み差分だけを使います。');
end;
function MoviePreparation(Project: TRigmMovieProject; Diagnostics,DiagnosticJob: TJSONObject;
  const OutputPath: string; PreviewCurrent: Boolean): TJSONObject;
var Issues,Steps: TJSONArray; TotalIssues,Pending,Unselected: Integer; AudioOK,CharacterOK,OutputOK,EngineOK,BgmOK: Boolean;
  Target,Directory: string; Duration,EstimatedSeconds: Double; Staging,FreeBytes,TotalBytes,Unused: UInt64;
  procedure Issue(const Code,Message,Action,Scope: string; Blocking: Boolean; const Id: string='');
  begin
    Inc(TotalIssues); if Issues.Count>=20 then Exit;
    var O := TJSONObject.Create; O.AddPair('code',Code); O.AddPair('message',Message); O.AddPair('nextAction',Action);
    O.AddPair('scope',Scope); O.AddPair('subjectId',Id); AddB(O,'blocking',Blocking); Issues.AddElement(O);
  end;
  procedure Step(const Id,Title,Command: string; Ready: Boolean);
  begin
    var O := TJSONObject.Create; O.AddPair('id',Id); O.AddPair('title',Title); O.AddPair('command',Command); AddB(O,'ready',Ready); Steps.AddElement(O);
  end;
begin
  Result := TJSONObject.Create; Issues := TJSONArray.Create; Steps := TJSONArray.Create;
  Result.AddPair('issues',Issues); Result.AddPair('steps',Steps); TotalIssues := 0; Pending := 0; Unselected := 0;
  Target := OutputPath; if Target='' then Target := Project.OutputTarget;
  var Current := JS(Diagnostics,'key')=MoviePreparationKey(Project);
  AddB(Result,'diagnosticsCurrent',Current); Result.AddPair('diagnosticsJob',DiagnosticJob.Clone as TJSONObject);
  AddB(Result,'diagnosticsBusy',not JB(DiagnosticJob,'done',True)); AddB(Result,'readOnly',True); AddB(Result,'realSpeechVerified',False);
  var Capabilities := MovieCapabilities(nil);
  if Current and (Diagnostics.GetValue('assets')<>nil) and (JO(Diagnostics,'assets').GetValue('capabilities')<>nil) then begin
    Capabilities.Free; Capabilities := JO(Diagnostics,'assets').GetValue('capabilities').Clone as TJSONObject;
  end;
  Result.AddPair('capabilities',Capabilities);
  var Styles := TJSONArray.Create;
  if Current and (Diagnostics.GetValue('speakers')<>nil) then begin Styles.Free; Styles := JA(Diagnostics,'speakers').Clone as TJSONArray; end;
  Result.AddPair('availableStyles',Styles);
  var Engine := TJSONObject.Create; Engine.AddPair('url',Project.EngineUrl); EngineOK := Current and JB(Diagnostics,'engineConnected');
  AddB(Engine,'connected',EngineOK); AddB(Engine,'checked',Current); Engine.AddPair('message','接続確認は話者一覧の読取だけです。修復や音声合成は行いません。'); Result.AddPair('engine',Engine);
  for var C in Project.Cues do if not Project.AudioReady(C) then Inc(Pending);
  AudioOK := (Project.Cues.Count>0) and (Pending=0);
  if Project.Cues.Count=0 then Issue('script_empty','自分の台本を入力またはファイルから取り込んでください。','movie-import-script','script',True);
  for var S in Project.Speakers do begin
    var Used := False; for var C in Project.Cues do if (C.SpeakerId=S.Id) and (C.VoiceStyleId<0) then Used := True;
    if not Used then Continue;
    var Found := False; for var V in Styles do if JI(TJSONObject(V),'styleId')=S.StyleId then Found := True;
    if (S.StyleId<0) or (EngineOK and not Found) then begin
      Inc(Unselected); Issue('speaker_unavailable','話者 '+S.Id+' に利用可能な音声を割り当ててください。','movie-update-speaker','audio',not AudioOK,S.Id);
    end;
  end;
  for var C in Project.Cues do if C.VoiceStyleId>=0 then begin
    var Found := False; for var V in Styles do if JI(TJSONObject(V),'styleId')=C.VoiceStyleId then Found := True;
    if EngineOK and not Found then begin
      Inc(Unselected); Issue('speaker_unavailable','Cue voice style is not present in the connected engine','movie-update-cue','audio',not Project.AudioReady(C),C.Id);
    end;
  end;
  if not EngineOK then begin
    var Code := 'engine_unchecked'; var Message := 'VOICEVOX接続を診断してください。';
    if Current then begin Code := 'engine_unavailable'; Message := 'VOICEVOXへ接続できません。起動と接続先を確認してください。 '+JS(Diagnostics,'engineError'); end;
    Issue(Code,Message,'movie-diagnostics-refresh','audio',not AudioOK);
  end;
  if Pending>0 then Issue('audio_pending',Pending.ToString+'件の音声が未生成または設定変更で無効です。','movie-audio-generate','export',True);
  BgmOK := True;
  if Project.BgmFile<>'' then begin
    var BgmPath := ResolveMoviePath(Project.FileName,Project.BgmFile);
    try
      if not FileExists(BgmPath) then begin
        BgmOK := False; Issue('bgm_missing','BGMが見つかりません。選び直すか解除してください。','movie-update-project','export',True);
      end else if not SameText(ExtractFileExt(BgmPath),'.wav') or (TFile.GetSize(BgmPath)<44) or (TFile.GetSize(BgmPath)>128*1024*1024) then begin
        BgmOK := False; Issue('bgm_invalid','BGMには44bytes～128MiBのPCM16 WAVを選択してください。','movie-update-project','export',True);
      end else if not Current then begin
        BgmOK := False; Issue('bgm_unchecked','BGM素材の読込診断を待つか、診断を更新してください。','movie-diagnostics-refresh','export',True);
      end else if JS(Diagnostics,'materialError')<>'' then begin
        BgmOK := False; Issue('bgm_material_invalid','BGMを含む素材診断に失敗しました。 '+JS(Diagnostics,'materialError'),'movie-diagnostics-refresh','export',True);
      end;
    except
      on E: Exception do begin BgmOK := False; Issue('bgm_unreadable','BGMを読めません。 '+E.Message,'movie-update-project','export',True); end;
    end;
  end;
  CharacterOK := True;
  for var Character in Project.Characters do if Character.Visible and (Character.FileName<>'@sample') and
    not FileExists(ResolveMoviePath(Project.FileName,Character.FileName)) then begin
    CharacterOK := False; Issue('character_missing','Character source is missing: '+Character.FileName,'movie-update-character','export',True,Character.Id);
  end;
  for var Scene in Project.Scenes do if MatchText(Scene.DisplayMode,['image','both']) and (Scene.Image<>'') and not FileExists(ResolveMoviePath(Project.FileName,Scene.Image)) then begin
    CharacterOK := False; Issue('scene_image_missing','Scene image is missing: '+Scene.Image,'movie-update-scene','export',True,Scene.Id);
  end;
  if (Project.CharacterFile='') and (Project.Characters.Count=0) then Issue('character_none','キャラクター未選択です。字幕中心の動画は作れます。人物を出すにはRIGMを選択してください。','movie-update-project','character',False)
  else if not Current then begin CharacterOK := False; Issue('material_unchecked','素材参照と利用できる演技を診断してください。','movie-diagnostics-refresh','character',False); end
  else if JS(Diagnostics,'materialError')<>'' then begin CharacterOK := False; Issue('material_invalid',JS(Diagnostics,'materialError'),'movie-update-project','export',True); end
  else if not JB(Capabilities,'headBodyMotion') then Issue('motion_unavailable','この素材の頭・上半身の動きにはボーンとメッシュの準備が必要です。静止表示と既存差分を使えます。','safe-acting','character',False);
  if Current and (JS(Diagnostics,'actingError')<>'') then begin CharacterOK := False; Issue('acting_unavailable',JS(Diagnostics,'actingError'),'safe-acting','export',True); end;
  for var C in Project.Cues do if (C.Background<>'') and not FileExists(ResolveMoviePath(Project.FileName,C.Background)) then begin
    CharacterOK := False; Issue('background_missing','背景画像が見つかりません。 '+C.Background,'movie-update-cue','export',True,C.Id);
  end;
  var Mp4 := SameText(ExtractFileExt(Target),'.mp4'); OutputOK := Target<>'';
  if Target='' then Issue('output_missing','新しいAVIまたはMP4の出力先を設定してください。','movie-update-project','output',True)
  else if FileExists(Target) then begin OutputOK := False; Issue('output_exists','出力先は既に存在します。別のファイル名を使ってください。','movie-update-project','output',True); end
  else if not Mp4 and not SameText(ExtractFileExt(Target),'.avi') then begin OutputOK := False; Issue('output_format','出力拡張子は.aviまたは.mp4です。','movie-update-project','output',True); end;
  var FfmpegOK := FileExists(Project.FfmpegExe) and SameText(ExtractFileName(Project.FfmpegExe),'ffmpeg.exe');
  if Mp4 and not FfmpegOK then begin OutputOK := False; Issue('ffmpeg_missing','MP4には既存のffmpeg.exeを選択してください。AVIはFFmpegなしで出力できます。','movie-update-project','output',True); end;
  Duration := Project.Duration; EstimatedSeconds := Duration*386.265/180*(Project.Width*Project.Height/2073600.0)*(Project.Fps/30);
  if Project.EncodeProfile='balanced' then EstimatedSeconds := EstimatedSeconds*1.3;
  if Project.EncodeProfile='quality' then EstimatedSeconds := EstimatedSeconds*1.8;
  // MP4 streams one raw frame to FFmpeg; disk staging contains only PCM audio and compressed output.
  if Mp4 then Staging := Round(Duration*(Project.Width*Project.Height*Project.Fps*0.025+96000))
  else Staging := Round(Duration*(Project.Width*Project.Height*Project.Fps*0.06+196000));
  FreeBytes := 0;
  if Target<>'' then try
    Directory := ExtractFilePath(ExpandFileName(Target));
    while (Directory<>'') and not DirectoryExists(Directory) do begin var Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(Directory))); if Parent=Directory then Break; Directory := Parent; end;
    if (Directory<>'') and GetDiskFreeSpaceEx(PChar(Directory),FreeBytes,TotalBytes,@Unused) then begin
      if FreeBytes<Staging then begin OutputOK := False; Issue('disk_space_low','空き容量が一時ファイルの概算より少ないため、出力先かサイズを変更してください。','movie-update-project','output',True); end;
    end else begin OutputOK := False; Issue('output_drive_unavailable','出力先のドライブと空き容量を確認できません。利用可能な保存先を選んでください。','movie-update-project','output',True); end;
  except OutputOK := False; Issue('output_path_invalid','出力先のパスを確認してください。','movie-update-project','output',True); end;
  if not Mp4 and (Staging>1800000000) then Issue('avi_staging_risk','一時AVIの2GB制限に近い概算です。サイズ・fps・長さを下げてください。','movie-update-project','output',False);
  var Estimate := TJSONObject.Create; AddN(Estimate,'durationSeconds',Duration); AddB(Estimate,'durationEstimated',not AudioOK);
  AddN(Estimate,'exportSeconds',EstimatedSeconds); AddN(Estimate,'stagingBytes',Staging); AddN(Estimate,'freeBytes',FreeBytes);
  Estimate.AddPair('basis','historical renderer heuristic from 1080p30 fast Kiritan 180s / 386.265s; material and CPU dependent; raw streaming and quality factors unmeasured');
  if Mp4 then begin
    Estimate.AddPair('backend','ffmpeg-raw-bgra-pipe');
    Estimate.AddPair('stagingBasis','heuristic: 48000 Hz mono PCM plus compressed MP4; no intermediate AVI; bitrate is content dependent');
  end else begin
    Estimate.AddPair('backend','legacy-mjpeg-avi');
    Estimate.AddPair('stagingBasis','heuristic: MJPEG AVI including PCM; legacy 2 GB AVI limit remains');
  end;
  Estimate.AddPair('writePermission','not probed: read-only diagnosis'); Result.AddPair('estimate',Estimate);
  Step('script','1 台本を取り込む','movie-import-script',Project.Cues.Count>0);
  Step('setup','2 話者・キャラクター・素材を選ぶ','movie-diagnostics-refresh',EngineOK and (Unselected=0) and CharacterOK);
  Step('audio','3 音声を生成する','movie-audio-generate',AudioOK);
  Step('preview','4 プレビューで確認する','movie-preview',PreviewCurrent);
  Step('export','5 新しいファイルへ出力する','movie-export',AudioOK and CharacterOK and BgmOK and OutputOK);
  var Next := 'movie-import-script'; var Message := '自分の台本を貼り付けて取り込んでください。';
  if Project.Cues.Count>0 then begin
    Next := 'movie-diagnostics-refresh'; Message := '接続・話者・素材を診断してください。';
    if EngineOK and (Unselected>0) and not AudioOK then begin Next := 'movie-update-speaker'; Message := '右側で話者ごとに音声を選び、音声設定を適用してください。'; end
    else if Current and not CharacterOK then begin
      Next := 'movie-update-project'; Message := '見つからない素材を選び直してください。';
      if JS(Diagnostics,'actingError')<>'' then begin Next := 'safe-acting'; Message := '不足する差分を確認し、利用できる演技方式へ戻してください。'; end;
    end
    else if EngineOK and (Unselected=0) and CharacterOK then begin
      Next := 'movie-audio-generate'; Message := '音声を生成してください。';
      if AudioOK then begin Next := 'movie-preview'; Message := 'プレビューで確認し、出力先を設定してください。'; if OutputOK then Message := 'プレビューで確認してから、新しい出力先へ書き出せます。'; end;
    end else if AudioOK and CharacterOK then begin Next := 'movie-preview'; Message := '保存済み音声でプレビューと出力ができます。'; end;
    if AudioOK and CharacterOK and PreviewCurrent then begin
      if OutputOK then begin Next := 'movie-export'; Message := '準備できました。新しい出力先へ書き出せます。'; end
      else begin Next := 'movie-update-project'; Message := '出力先・FFmpeg・空き容量の診断項目を確認してください。'; end;
    end;
  end;
  Result.AddPair('nextAction',Next); Result.AddPair('message',Message); AddN(Result,'totalIssues',TotalIssues);
  var NextArgs := TJSONObject.Create; Result.AddPair('nextArgs',NextArgs);
  var NextCommand := Next;
  if Next='safe-acting' then begin
    NextCommand := 'movie-update-cue'; NextArgs.AddPair('id','choose affected cue from movie-project');
    var Acting := ParseObject('{"mouthMode":"auto","blinkMode":"auto","variants":[]}');
    if not JB(Capabilities,'headBodyMotion') then begin AddN(Acting,'headGain',0); AddN(Acting,'bodyGain',0); end;
    NextArgs.AddPair('acting',Acting);
  end;
  Result.AddPair('nextCommand',NextCommand);
  AddB(Result,'nextArgsRequireUserValues',MatchText(Next,['movie-import-script','movie-update-speaker','movie-update-project','safe-acting']));
  Result.AddPair('mutationPrecondition','read latest movie-status projectId/revision before applying suggested edits');
  AddN(Result,'audioPending',Pending); AddB(Result,'canGenerateAudio',EngineOK and (Unselected=0) and (Project.Cues.Count>0));
  AddB(Result,'canExport',AudioOK and CharacterOK and BgmOK and OutputOK); AddB(Result,'canPreview',CharacterOK and BgmOK and (Project.Cues.Count>0));
  Result.AddPair('outputPath',Target); AddB(Result,'ffmpegConfigured',FfmpegOK);
  AddB(Result,'previewCurrent',PreviewCurrent); AddB(Result,'bgmReady',BgmOK);
  AddN(Result,'bgmFadeOutEffective',Min(Project.BgmFadeOut,Project.Duration));
end;
function MovieExamples: TJSONArray;
begin
  Result := TJSONArray.Create;
  var O := TJSONObject.Create; O.AddPair('id','fictional-short'); O.AddPair('title','架空の短い紹介例'); O.AddPair('kind','fictional_example');
  O.AddPair('text','# 架空の紹介例'+sLineBreak+'narrator:これは架空の小さな喫茶店の紹介例です。'+sLineBreak+'narrator:木の椅子と、静かな音楽のあるお店です。'); Result.AddElement(O);
  O := TJSONObject.Create; O.AddPair('id','intro-three-minute'); O.AddPair('title','3分紹介用の構成テンプレート'); O.AddPair('kind','structure_template');
  AddN(O,'suggestedSeconds',180); AddB(O,'durationGuaranteed',False);
  O.AddPair('text','# 0:00–0:15 導入'+sLineBreak+'narrator:【紹介する対象と、この動画で伝えたいこと】'+sLineBreak+'# 0:15–0:45 概要'+sLineBreak+'narrator:【対象の概要を、自分の言葉で説明】'+sLineBreak+'# 0:45–1:30 特徴'+sLineBreak+'narrator:【特徴を二つか三つ、具体例とともに紹介】'+sLineBreak+'# 1:30–2:15 使い方・体験'+sLineBreak+'narrator:【使い方や体験を、順序に沿って紹介】'+sLineBreak+'# 2:15–2:45 補足'+sLineBreak+'narrator:【注意点や向いている場面】'+sLineBreak+'# 2:45–3:00 まとめ'+sLineBreak+'narrator:【伝えたいことと、次にしてほしいこと】'); Result.AddElement(O);
end;
end.
