// ScriptOrderCheckの専用台本で、第16段階から背景受渡し・保存・描画・MP4まで確認する。
function BgArgs: TJSONObject;
begin
  Result := TJSONObject.Create; Result.AddPair('projectId',W.ScriptDraft.Id);
  AddN(Result,'revision',W.ScriptDraft.Revision); Result.AddPair('sceneId',RigmCommonBackgroundId);
end;
procedure BgPng(const Path: string; Width,Height: Integer; Marker: Boolean);
begin
  ForceDirectories(ExtractFilePath(Path)); var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try
    Bitmap.SetSize(Width,Height); Bitmap.Canvas.Brush.Color := clLime; Bitmap.Canvas.FillRect(Rect(0,0,Width,Height));
    if Marker then begin Bitmap.Canvas.Brush.Color := clBlue;
      Bitmap.Canvas.FillRect(Rect(Width div 2-5,Height div 2-5,Width div 2+5,Height div 2+5)); end;
    Png.Assign(Bitmap); Png.SaveToFile(Path);
  finally Png.Free; Bitmap.Free; end;
end;
function BgBlue(Bitmap: TBitmap; X,Y: Integer): Boolean;
begin
  var Colour := ColorToRGB(Bitmap.Canvas.Pixels[X,Y]);
  Result := (GetBValue(Colour)>200) and (GetRValue(Colour)<60) and (GetGValue(Colour)<60);
end;
procedure BgSquare(Bitmap: TBitmap; const Bounds: TRect; const Context: string);
begin
  var Center := Bounds.CenterPoint; var Across := 0; var Down := 0;
  for var X := Bounds.Left to Bounds.Right-1 do if BgBlue(Bitmap,X,Center.Y) then Inc(Across);
  for var Y := Bounds.Top to Bounds.Bottom-1 do if BgBlue(Bitmap,Center.X,Y) then Inc(Down);
  Check((Across>5) and (Abs(Across-Down)<=1),Context+' preserves the square marker aspect ratio');
end;
procedure BgDecode(const Path: string);
var Api: TRigmFFmpegApi; Format: PAVFormatContext; Context: PAVCodecContext;
  Packet: PAVPacket; Frame: PAVFrame; Frames: Integer; Green: Boolean;
  procedure Receive;
  begin
    while True do begin
      var Code := Api.avcodec_receive_frame(Context,Frame);
      if (Code=AVERROR_EAGAIN) or (Code=AVERROR_EOF) then Exit;
      Api.Check(Code,'background decode'); Inc(Frames);
      Check((Frame.width=320) and (Frame.height=180),'background MP4 retains video resolution');
      Green := Green or (PByte(NativeUInt(Frame.data[0])+NativeUInt(Frame.linesize[0])*80+5)^>110);
    end;
  end;
begin
  Api := TRigmFFmpegApi.Create; Format := nil; Context := nil; Packet := nil; Frame := nil; Frames := 0; Green := False;
  try
    var Name := UTF8String(Path); Api.Check(Api.avformat_open_input(@Format,PAnsiChar(Name),nil,nil),'open background MP4');
    Api.Check(Api.avformat_find_stream_info(Format,nil),'background streams'); var Index := -1;
    for var I := 0 to Integer(Format.nb_streams)-1 do begin
      var Stream := PAVStream(PPointer(NativeUInt(Format.streams)+NativeUInt(I)*SizeOf(Pointer))^);
      if Stream.codecpar.codec_type<>AVMEDIA_TYPE_VIDEO then Continue;
      Index := I; var Decoder := Api.avcodec_find_decoder(Stream.codecpar.codec_id); Context := Api.avcodec_alloc_context3(Decoder);
      Api.Check(Api.avcodec_parameters_to_context(Context,Stream.codecpar),'background parameters');
      Api.Check(Api.avcodec_open2(Context,Decoder,nil),'background decoder'); Break;
    end;
    Check(Index>=0,'background MP4 has a video stream'); Packet := Api.av_packet_alloc; Frame := Api.av_frame_alloc;
    while Api.av_read_frame(Format,Packet)>=0 do begin
      if Packet.stream_index=Index then begin Api.Check(Api.avcodec_send_packet(Context,Packet),'background packet'); Receive; end;
      Api.av_packet_unref(Packet);
    end;
    Api.Check(Api.avcodec_send_packet(Context,nil),'background flush'); Receive;
    Check((Frames=2) and Green,'all background MP4 frames decode with the adopted green image');
  finally
    if Frame<>nil then Api.av_frame_free(@Frame); if Packet<>nil then Api.av_packet_free(@Packet);
    if Context<>nil then Api.avcodec_free_context(@Context); if Format<>nil then Api.avformat_close_input(@Format); Api.Free;
  end;
end;
procedure BgRendering;
begin
  var P := TRigmMovieProject.Create;
  try
    P.Width := 320; P.Height := 180; P.Fps := 5;
    var Scene := TRigmMovieScene.Create; Scene.Title := ''; Scene.DisplayMode := 'none'; P.Scenes.Add(Scene);
    var Cue := TRigmMovieCue.Create; Cue.Scene := Scene.Id; Cue.AudioSeconds := 0.4; Cue.Pause := 0; P.Cues.Add(Cue);
    var Exact := TPath.Combine(Root,'Background\exact.png'); BgPng(Exact,320,180,True); P.ThemeBackground := Exact;
    var SourceHash := THashSHA2.GetHashStringFromFile(Exact); var B := RenderComposition(P,0.05,nil);
    try
      Check((B.Width=320) and (B.Height=180) and (ColorToRGB(B.Canvas.Pixels[5,80])=ColorToRGB(clLime)),
        'matching-size common background appears across the central layout');
      BgSquare(B,Rect(0,0,320,180),'matching-size background');
      B.SaveToFile(TPath.Combine(Root,'Background\exact-render.bmp'));
    finally B.Free; end;
    Check(SourceHash=THashSHA2.GetHashStringFromFile(Exact),'matching-size image remains byte-for-byte unchanged');
    for var Portrait in [False,True] do begin
      var Path := TPath.Combine(Root,'Background\wide.png');
      if Portrait then begin Path := TPath.Combine(Root,'Background\portrait.png'); BgPng(Path,100,200,True); end
      else BgPng(Path,100,50,True);
      P.ThemeBackground := Path; var Hash := THashSHA2.GetHashStringFromFile(Path); B := RenderComposition(P,0.05,nil);
      try
        BgSquare(B,Rect(0,0,320,180),'mismatched background '+Portrait.ToString);
        Check((ColorToRGB(B.Canvas.Pixels[5,80])=ColorToRGB(clLime)) and
          (ColorToRGB(B.Canvas.Pixels[315,80])=ColorToRGB(clLime)),'mismatched image fills the background area '+Portrait.ToString);
        B.SaveToFile(TPath.Combine(Root,'Background\fit-'+Portrait.ToString+'.bmp'));
      finally B.Free; end;
      Check(Hash=THashSHA2.GetHashStringFromFile(Path),'render fitting preserves source bytes '+Portrait.ToString);
    end;
    P.ThemeBackground := TPath.Combine(Root,'Background\wide.png'); P.Layout := 'l';
    for var Direction in ['left','right'] do begin
      P.LDirection := Direction; var Area := ScaleLayoutRect(MovieLayoutRegions('l',Direction).Image,P.Width,P.Height);
      B := RenderComposition(P,0.05,nil);
      try
        BgSquare(B,Area,'empty L image region '+Direction);
        Check(ColorToRGB(B.Canvas.Pixels[Area.Left-1,Area.CenterPoint.Y])=ColorToRGB(P.BackgroundColor),
          'L background is clipped before the neighbouring area '+Direction);
        Check(ColorToRGB(B.Canvas.Pixels[Area.Right+1,Area.CenterPoint.Y])=ColorToRGB(P.BackgroundColor),
          'L background is clipped after the image area '+Direction);
      finally B.Free; end;
      Scene.Image := Exact; Scene.DisplayMode := 'image'; B := RenderComposition(P,0.05,nil);
      try
        Check(ColorToRGB(B.Canvas.Pixels[Area.Left+1,Area.CenterPoint.Y])=ColorToRGB(P.BackgroundColor),
          'existing L scene image keeps its fit margin without the common fallback '+Direction);
      finally B.Free; end;
      var BackgroundPath := P.ThemeBackground; P.ThemeBackground := TPath.Combine(Root,'Background\missing.png');
      try ValidateCompositionMaterials(P); Check(True,'unused common background is optional in L material validation '+Direction);
      finally P.ThemeBackground := BackgroundPath; end;
      Scene.Image := ''; Scene.DisplayMode := 'none';
      Cue.Background := Exact; B := RenderComposition(P,0.05,nil);
      try Check(ColorToRGB(B.Canvas.Pixels[Area.Left+1,Area.CenterPoint.Y])=ColorToRGB(clLime),
        'hidden cue image does not suppress the L fallback '+Direction); finally B.Free; end;
      Cue.Background := '';
    end;
    var BackgroundPath := P.ThemeBackground; P.ThemeBackground := TPath.Combine(Root,'Background\missing.png');
    var Rejected := False;
    try ValidateCompositionMaterials(P); except on E: Exception do Rejected := True; end;
    P.ThemeBackground := BackgroundPath; Check(Rejected,'missing common background is reported when the L fallback needs it');
    P.ThemeBackground := ''; B := RenderComposition(P,0.05,nil);
    try Check(ColorToRGB(B.Canvas.Pixels[100,80])=ColorToRGB(P.BackgroundColor),'L layout renders normally without a common background'); finally B.Free; end;
    P.Layout := 'theme'; P.ThemeBackground := Exact;
    B := RenderMoviePreview(P,nil,0.05,nil,160,120);
    try Check((B.Width<P.Width) and (P.Width=320) and (P.Height=180),'bounded background preview restores export resolution'); finally B.Free; end;
    var Audio := TRigmPcm.Create;
    try
      Audio.Rate := 48000; SetLength(Audio.Samples,19200); var Output := TPath.Combine(Root,'Background\common.mp4');
      StreamMovieMp4(P,nil,Audio,Output,function: Boolean begin Result := False; end,nil,nil,nil);
      BgDecode(Output);
    finally Audio.Free; end;
  finally P.Free; end;
end;
procedure BgChunkTransfer(const Path: string; const SceneId: string=RigmCommonBackgroundId; Rename: Boolean=False);
begin
  W.RequestScriptSceneImage(SceneId); var RequestId := JS(ScriptSceneRequest(W.ScriptDraft,SceneId),'requestId');
  var Data := TFile.ReadAllBytes(Path); var A := BgArgs;
  try
    PsdJson.Put(A,'sceneId',SceneId);
    A.AddPair('requestId',RequestId); A.AddPair('sha256',THashSHA2.GetHashStringFromFile(Path));
    AddN(A,'byteCount',Length(Data)); A.AddPair('mimeType','image/png'); A.AddPair('provenance','test-fixture');
    var Reply := W.ExecuteScriptImageTransfer('image-transfer-begin',A); var Id := JS(Reply,'transferId'); Reply.Free;
    var Offset := 0; var Encoding := TBase64Encoding.Create(0);
    try
      while Offset<Length(Data) do begin
        var Chunk := Copy(Data,Offset,Min(RigmImageChunkBytes,Length(Data)-Offset)); var Args := TJSONObject.Create;
        try Args.AddPair('transferId',Id); AddN(Args,'offset',Offset); Args.AddPair('data',Encoding.EncodeBytesToString(Chunk));
          Reply := W.ExecuteScriptImageTransfer('image-transfer-chunk',Args); Reply.Free;
        finally Args.Free; end;
        Inc(Offset,Length(Chunk));
      end;
    finally Encoding.Free; end;
    A.AddPair('transferId',Id); Reply := W.ExecuteScriptImageTransfer('image-transfer-finish',A); Reply.Free;
    var Deadline := GetTickCount64+10000;
    repeat
      Reply := W.ExecuteScriptImageTransfer('image-transfer-status',A); var State := JS(Reply,'state'); var Failure := JS(Reply,'error'); Reply.Free;
      if State='ready' then Break;
      if (State='failed') or (GetTickCount64>Deadline) then raise Exception.Create('Owned background transfer: '+Failure); Sleep(10);
    until False;
    if Rename then begin
      var Args := TJSONObject.Create;
      try Args.AddPair('projectId',W.ScriptDraft.Id); AddN(Args,'revision',W.ScriptDraft.Revision); Args.AddPair('sceneId',SceneId);
        Args.AddPair('title','画像転送中に変更した名前'); Reply := W.Command('app-script-edit-scene',Args); Reply.Free;
      finally Args.Free; end;
      PsdJson.Put(A,'revision',TJSONNumber.Create(W.ScriptDraft.Revision));
    end;
    Reply := W.ExecuteScriptImageTransfer('image-transfer-adopt',A); Reply.Free;
    Check(THashSHA2.GetHashStringFromFile(W.ScriptDraft.ImageTarget(SceneId).Image)=THashSHA2.GetHashStringFromFile(Path),
      'PNG chunk transfer adopts '+SceneId+' without resizing, including after a display-name change');
  finally A.Free; end;
end;
procedure CheckCommonBackground;
begin
  var Frame := StageFrame(TRigmScriptScenesFrame) as TRigmScriptScenesFrame; Frame.RefreshState;
  var Rows := TList<TRigmSceneImageRow>.Create;
  try
    for var I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TRigmSceneImageRow then Rows.Add(TRigmSceneImageRow(Frame.Components[I]));
    var Row := Rows[0]; var Count := W.ScriptDraft.Scenes.Count; var Duration := W.ScriptDraft.Duration;
    Check((Rows.Count=Count+2) and (Row.SceneId=RigmCommonBackgroundId) and (Row.Top<Rows[1].Top),
      'dedicated common background is the first stage-16 item');
    Check((Rows[1].Number.Caption='1') and (W.ScriptDraft.Scene(RigmCommonBackgroundId)=nil),
      'background does not become a numbered dialogue scene');
    Check(Row.Description.ReadOnly and not Row.Position.Visible,'common background has guidance instead of a subtitle or position editor');
    Check(ScriptThumbnailSourcesReady(W.ScriptDraft),'empty optional background does not block completed scenes');
    Row.Prompt.Text := '専用の共通背景'; Check(Frame.RequestFinish,'native background memo applies to the shared model');
    for var Scene in W.ScriptDraft.Scenes do if MovieChartEnabled(Scene.Chart) then
      Check(Scene.DisplayMode='image','flushing background input preserves the independent summary chart display');
    Check(W.ScriptDraft.CommonBackground.ImagePrompt='専用の共通背景','common background instructions persist independently of scenes');
    Check(not ScriptThumbnailSourcesReady(W.ScriptDraft),'requested background requires its own adopted image and human confirmation');
    W.SelectScriptScene(RigmCommonBackgroundId); W.RequestUnapprovedScriptImages;
    var Request := ScriptSceneRequest(W.ScriptDraft,RigmCommonBackgroundId);
    Check((JS(Request,'target')='common-background') and (JI(Request,'width')=W.ScriptDraft.Width) and
      (JI(Request,'height')=W.ScriptDraft.Height),'common background generation requests the actual video resolution');
    var OldId := JS(Request,'requestId'); Row.Prompt.Text := '変更後の共通背景'; Check(Frame.RequestFinish,'background edits apply while a request is pending');
    var Rejected := False; try RequireSceneImageRequest(W.ScriptDraft,RigmCommonBackgroundId,OldId); except on E: Exception do Rejected := True; end;
    Check(Rejected,'old background request is rejected after prompt changes');
    W.RequestScriptSceneImage(RigmCommonBackgroundId); Request := ScriptSceneRequest(W.ScriptDraft,RigmCommonBackgroundId);
    var Width := W.ScriptDraft.Width; W.ScriptDraft.Width := 1280; Rejected := False;
    try RequireSceneImageRequest(W.ScriptDraft,RigmCommonBackgroundId,JS(Request,'requestId')); except on E: Exception do Rejected := True; end;
    W.ScriptDraft.Width := Width; Check(Rejected,'old background request is rejected after video resolution changes');
    var Path := TPath.Combine(Main.DataRoot,'Exchange\common-background.png'); BgPng(Path,W.ScriptDraft.Width,W.ScriptDraft.Height,False);
    var A := BgArgs;
    try A.AddPair('requestId',JS(Request,'requestId')); A.AddPair('path','Exchange\common-background.png');
      A.AddPair('sha256',THashSHA2.GetHashStringFromFile(Path)); A.AddPair('provenance','test-fixture');
      W.DeliverScriptSceneImage(A);
    finally A.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Path)=THashSHA2.GetHashStringFromFile(W.ScriptDraft.ThemeBackground),
      'exact-resolution generated file is adopted unchanged into managed assets');
    Frame.RefreshState; Check((Row.Picture.Picture.Width=W.ScriptDraft.Width) and (Row.Picture.Picture.Height=W.ScriptDraft.Height),
      'background row displays the adopted image dimensions');
    Check(not ScriptThumbnailSourcesReady(W.ScriptDraft),'image adoption alone does not silently confirm the background');
    Row.Approved.Checked := True; Row.Approved.OnClick(Row.Approved);
    Check(W.ScriptDraft.CommonBackground.ImageApproved and ScriptThumbnailSourcesReady(W.ScriptDraft),'native checkbox confirms the background and permits final thumbnail creation');
    var S := TRigmMovieSession.Create;
    try
      S.SetProject(W.ScriptDraft.Clone); A := TJSONObject.Create;
      try A.AddPair('projectId',S.Project.Id); AddN(A,'revision',S.Project.Revision); A.AddPair('themeBackground','');
        Rejected := False; try var Reply := S.Execute('update-project',A); Reply.Free; except on E: Exception do Rejected := True; end;
        Check(Rejected and (S.Project.ThemeBackground<>''),'generic movie update cannot replace an approved common background');
      finally A.Free; end;
    finally S.Free; end;
    Row.Approved.Checked := False; Row.Approved.OnClick(Row.Approved);
    Check(not W.ScriptDraft.CommonBackground.ImageApproved,'human can unlock the common background for correction');
    var Mismatch := TPath.Combine(Root,'Background\incoming-wide.png'); BgPng(Mismatch,100,50,True);
    BgChunkTransfer(Mismatch); Frame.RefreshState;
    Check((Row.Picture.Picture.Width=100) and (Row.Picture.Picture.Height=50),'different-resolution image remains the original asset for fitting during rendering');
    W.RequestScriptSceneImage(RigmCommonBackgroundId); var Pending := JS(ScriptSceneRequest(W.ScriptDraft,RigmCommonBackgroundId),'requestId');
    W.SaveScriptDraft(False); RequireSceneImageRequest(W.ScriptDraft,RigmCommonBackgroundId,Pending);
    Check(True,'pending background request survives managed-asset relocation during save');
    var Saved := LoadMovie(W.ScriptDraft.FileName);
    try Check((Saved.CommonBackground.ImagePrompt='変更後の共通背景') and (Saved.ThemeBackground<>'') and
      (THashSHA2.GetHashStringFromFile(ResolveMoviePath(Saved.FileName,Saved.ThemeBackground))=THashSHA2.GetHashStringFromFile(Mismatch)),
      'save and reopen retain background instructions and the adopted image');
    finally Saved.Free; end;
    var Adopted := W.ScriptDraft.ThemeBackground; W.CancelScriptSceneImage(RigmCommonBackgroundId);
    Check(W.ScriptDraft.ThemeBackground=Adopted,'cancelling a request preserves the adopted background');
    Frame.RefreshState; Row.Approved.Checked := True; Row.Approved.OnClick(Row.Approved);
    A := BgArgs;
    try var Reply := W.ReadScriptScenes(A);
      try Check((JS(JO(Reply,'background'),'id')=RigmCommonBackgroundId) and
        (JA(JO(Reply,'background'),'sourceCues').Count=0) and (JI(Reply,'count')=Count) and
        (JS(TJSONObject(JA(Reply,'rows')[0]),'id')=W.ScriptDraft.Scenes[0].Id),
        'pipe publishes background separately while preserving normal scene pagination');
      finally Reply.Free; end;
    finally A.Free; end;
    Check((W.ScriptDraft.Scenes.Count=Count) and (Abs(W.ScriptDraft.Duration-Duration)<0.000001),
      'background editing does not add dialogue or change movie timing');
    Capture('common-background-stage16'); BgRendering;
  finally Rows.Free; end;
end;
