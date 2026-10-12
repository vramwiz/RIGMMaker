// 専用素材で必須・最終生成・参照・保存・末尾描画を確認する。実作品は操作しない。
procedure ThumbPng(const Path: string; Colour: TColor);
begin
  ForceDirectories(ExtractFilePath(Path)); var B := TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(320,180); B.Canvas.Brush.Color := Colour; B.Canvas.FillRect(Rect(0,0,320,180));
    P.Assign(B); P.SaveToFile(Path);
  finally P.Free; B.Free; end;
end;
{$IFDEF CHECK_BACKGROUND}
procedure ThumbDecode(const Path: string);
var Api: TRigmFFmpegApi; Format: PAVFormatContext; Context: PAVCodecContext;
  Packet: PAVPacket; Frame: PAVFrame; Frames: Integer; LastY,FirstY,FadeY: Byte;
  procedure Receive;
  begin
    while True do begin
      var Code := Api.avcodec_receive_frame(Context,Frame);
      if (Code=AVERROR_EAGAIN) or (Code=AVERROR_EOF) then Exit;
      Api.Check(Code,'thumbnail decode');
      var Y := PByte(NativeUInt(Frame.data[0])+NativeUInt(Frame.linesize[0])*80+5)^;
      if Frames=2 then FirstY := Y; // 0.4 sec: crossfade starts at the last red frame.
      if Frames=4 then FadeY := Y;  // 0.8 sec: blended frame.
      LastY := Y; Inc(Frames);
    end;
  end;
begin
  Api := TRigmFFmpegApi.Create; Format := nil; Context := nil; Packet := nil; Frame := nil;
  Frames := 0; LastY := 0; FirstY := 0; FadeY := 0;
  try
    var Name := UTF8String(Path); Api.Check(Api.avformat_open_input(@Format,PAnsiChar(Name),nil,nil),'open thumbnail MP4');
    Api.Check(Api.avformat_find_stream_info(Format,nil),'thumbnail streams'); var Index := -1;
    for var I := 0 to Integer(Format.nb_streams)-1 do begin
      var Stream := PAVStream(PPointer(NativeUInt(Format.streams)+NativeUInt(I)*SizeOf(Pointer))^);
      if Stream.codecpar.codec_type<>AVMEDIA_TYPE_VIDEO then Continue;
      Index := I; var Decoder := Api.avcodec_find_decoder(Stream.codecpar.codec_id); Context := Api.avcodec_alloc_context3(Decoder);
      Api.Check(Api.avcodec_parameters_to_context(Context,Stream.codecpar),'thumbnail parameters');
      Api.Check(Api.avcodec_open2(Context,Decoder,nil),'thumbnail decoder'); Break;
    end;
    Check(Index>=0,'thumbnail MP4 has a video stream'); Packet := Api.av_packet_alloc; Frame := Api.av_frame_alloc;
    while Api.av_read_frame(Format,Packet)>=0 do begin
      if Packet.stream_index=Index then begin Api.Check(Api.avcodec_send_packet(Context,Packet),'thumbnail packet'); Receive; end;
      Api.av_packet_unref(Packet);
    end;
    Api.Check(Api.avcodec_send_packet(Context,nil),'thumbnail flush'); Receive;
    Check(Frames=52,'encoded MP4 contains the story plus all ten thumbnail seconds');
    Check((FirstY>FadeY+5) and (FadeY>LastY+5) and (LastY>15),'decoded MP4 fades from red to blue without a black cut');
  finally
    if Frame<>nil then Api.av_frame_free(@Frame); if Packet<>nil then Api.av_packet_free(@Packet);
    if Context<>nil then Api.avcodec_free_context(@Context); if Format<>nil then Api.avformat_close_input(@Format); Api.Free;
  end;
end;
{$ENDIF}
procedure CheckThumbnailRendering;
begin
  var P := TRigmMovieProject.Create;
  try
    P.Width := 320; P.Height := 180; P.Fps := 5; P.Layout := 'theme';
    var Scene := TRigmMovieScene.Create; Scene.Title := ''; Scene.DisplayMode := 'none'; P.Scenes.Add(Scene);
    var Cue := TRigmMovieCue.Create; Cue.Scene := Scene.Id; Cue.AudioSeconds := 0.4; Cue.Pause := 0; P.Cues.Add(Cue);
    P.ThemeBackground := TPath.Combine(Root,'Thumbnail\red.png'); ThumbPng(P.ThemeBackground,clRed);
    P.Thumbnail.Image := TPath.Combine(Root,'Thumbnail\blue.png'); ThumbPng(P.Thumbnail.Image,clBlue);
    MaterializeScriptThumbnail(P); P.Validate;
    Check((P.Cues.Count=1) and (P.Scenes.Count=1) and (Abs(P.Duration-10.4)<0.000001),'thumbnail adds exactly ten seconds without synthetic dialogue');
    for var Time in [0.4,0.9,1.4,10.2] do begin
      var B := RenderComposition(P,Time,nil);
      try
        var Colour := ColorToRGB(B.Canvas.Pixels[5,80]); var Red := GetRValue(Colour); var Blue := GetBValue(Colour);
        if Time=0.4 then Check((Red=255) and (Blue=0),'thumbnail begins with the previous completed frame')
        else if Time=0.9 then Check((Red>=126) and (Red<=129) and (Blue>=126) and (Blue<=129),'halfway crossfade blends both images evenly')
        else Check((Red=0) and (Blue=255),'full thumbnail remains visible through the end at '+Time.ToString);
        var Png := TPngImage.Create; try Png.Assign(B); Png.SaveToFile(TPath.Combine(Root,'Thumbnail\frame-'+Round(Time*10).ToString+'.png')); finally Png.Free; end;
      finally B.Free; end;
    end;
    {$IFDEF CHECK_BACKGROUND}
    var Audio := TRigmPcm.Create;
    try Audio.Rate := 48000; SetLength(Audio.Samples,19200); var Output := TPath.Combine(Root,'Thumbnail\tail.mp4');
      StreamMovieMp4(P,nil,Audio,Output,function: Boolean begin Result := False; end,nil,nil,nil); ThumbDecode(Output);
    finally Audio.Free; end;
    {$ENDIF}
    var Thumb := P.EndCards.Remove(0);
    P.EndCards.AddElement(PsdJson.ObjectText('{"kind":"end","image":"'+StringReplace(P.ThemeBackground,'\','\\',[rfReplaceAll])+'","duration":2,"rect":{"x":0,"y":0,"width":0.4,"height":1},"reserved":[{"x":0.5,"y":0,"width":0.5,"height":1}]}'));
    P.EndCards.AddElement(Thumb);
    P.Validate; var B := RenderComposition(P,2.4,nil);
    try Check(ColorToRGB(B.Canvas.Pixels[5,80])=ColorToRGB(clRed),'crossfade also starts from an existing end card'); finally B.Free; end;
    MaterializeScriptThumbnail(P);
    Check((P.EndCards.Count=2) and (JS(TJSONObject(P.EndCards[0]),'kind')='end') and
      (JS(TJSONObject(P.EndCards[1]),'kind')='thumbnail'),'materialization preserves end-card order without duplicating the thumbnail');
    var Card := TJSONObject(P.EndCards[1]); PsdJson.Put(Card,'transitionSeconds',TJSONNumber.Create(11));
    var Rejected := False; try ValidateMovieEndCards(P.EndCards); except on E: Exception do Rejected := True; end;
    Check(Rejected,'transition longer than the thumbnail is rejected');
  finally P.Free; end;
end;
procedure CheckThumbnail;
begin
  var Frame := StageFrame(TRigmScriptScenesFrame) as TRigmScriptScenesFrame; Frame.RefreshState;
  var Row: TRigmSceneImageRow := nil; var Last: TRigmSceneImageRow := nil;
  for var I := 0 to Frame.ComponentCount-1 do if Frame.Components[I] is TRigmSceneImageRow then begin
    Last := TRigmSceneImageRow(Frame.Components[I]); if Last.SceneId=RigmThumbnailId then Row := Last;
  end;
  Check((Row<>nil) and (Row=Last) and (Pos('必須',Row.Number.Caption)>0),'mandatory thumbnail is the final stage-16 image row');
  Check(not Row.SceneName.Visible and Row.Description.ReadOnly and not Row.Position.Visible and
    (Pos('10秒',Row.Description.Text)>0),'thumbnail row explains its logo, duration and transition');
  Check(Trim(Row.Prompt.Text)<>'','thumbnail default instructions survive prior stage saves and input reflection');
  Check(ScriptThumbnailSourcesReady(W.ScriptDraft) and not ScriptScenesReady(W.ScriptDraft),'completed scenes still require the final thumbnail');
  var Rejected := False; try W.NextScriptDraft; except on E: Exception do Rejected := True; end;
  Check(Rejected and (W.CurrentScriptStage='scenes'),'cannot advance before creating and confirming a thumbnail');
  var Session := TRigmMovieSession.Create;
  try Session.SetProject(W.ScriptDraft.Clone); var Args := TJSONObject.Create;
    try Args.AddPair('projectId',Session.Project.Id); AddN(Args,'revision',Session.Project.Revision);
      var Target := TPath.Combine(Root,'Thumbnail\must-not-export.mp4'); Args.AddPair('path',Target);
      var Before := Session.Project.Json;
      try Rejected := False; try var Reply := Session.Execute('export',Args); Reply.Free; except on E: Exception do Rejected := Pos('サムネイル',E.Message)>0; end;
        var After := Session.Project.Json;
        try Check(Rejected and not Session.Busy and not FileExists(Target) and (Before.ToJSON=After.ToJSON),'video export rejects a missing thumbnail before changing output or starting a worker'); finally After.Free; end;
      finally Before.Free; end;
    finally Args.Free; end;
    Args := TJSONObject.Create;
    try var Reply := Session.Execute('preparation',Args);
      try Check(not JB(Reply,'canExport') and (JS(Reply,'nextAction')='app-script-status'),'preparation directs an old editor project back to the required image stage');
      finally Reply.Free; end;
    finally Args.Free; end;
  finally Session.Free; end;
  Rejected := False; try W.EditScriptScene(RigmThumbnailId,'','','none'); except on E: Exception do Rejected := True; end;
  Check(Rejected and (W.ScriptDraft.Thumbnail.DisplayMode='image'),'thumbnail cannot be changed to an omitted or text-only scene');
  var Id := W.ScriptDraft.Scenes[0].Id; W.SetScriptSceneApproved(Id,False);
  Rejected := False; try W.RequestScriptSceneImage(RigmThumbnailId); except on E: Exception do Rejected := True; end;
  Check(Rejected,'thumbnail generation waits until all source scenes are confirmed'); W.SetScriptSceneApproved(Id,True);
  W.RequestScriptSceneImage(RigmThumbnailId); var Request := ScriptSceneRequest(W.ScriptDraft,RigmThumbnailId);
  var RequestId := JS(Request,'requestId');
  Check((JS(Request,'target')='thumbnail') and (JI(Request,'width')=W.ScriptDraft.Width) and
    (JI(Request,'height')=W.ScriptDraft.Height) and (Pos('ピクセル',JS(Request,'sizeInstruction'))>0),'thumbnail request carries the current video size and fitting instruction');
  Check((JS(Request,'logoText')='漫画　'+JS(W.ScriptDraft.ScriptWizard,'titleInput')) and
    (Pos(JS(Request,'logoText'),JS(Request,'generationInstruction'))>0) and
    (JA(JO(Request,'sources'),'characters').Count>0),'thumbnail request carries a large manga-title logo and the selected characters');
  {$IFDEF CHECK_BACKGROUND}
  Check(JA(JO(Request,'sources'),'images').Count>=2,'thumbnail generation receives both the earlier scene image and the common background');
  {$ENDIF}
  var Deadline := GetTickCount64+10000; var PreviewPath := '';
  repeat
    var A := TJSONObject.Create;
    try A.AddPair('projectId',W.ScriptDraft.Id); AddN(A,'revision',W.ScriptDraft.Revision); var Reply := W.ReadScriptScenes(A);
      try var Thumb := JO(Reply,'thumbnail'); Check(JB(Thumb,'required') and (Thumb.GetValue('sourceCues')=nil),'pipe identifies thumbnail as mandatory without dialogue');
        PreviewPath := JS(TJSONObject(JA(JO(JO(Thumb,'imageRequest'),'sources'),'characters')[0]),'previewPath');
      finally Reply.Free; end;
    finally A.Free; end;
    if PreviewPath<>'' then Break; CheckSynchronize(0); Application.ProcessMessages; Sleep(10);
  until GetTickCount64>Deadline;
  Check((PreviewPath<>'') and FileExists(PreviewPath),'pipe exposes an ordinary PNG reference for the character artwork');
  var Ref := TPngImage.Create;
  try Ref.LoadFromFile(PreviewPath); Check((Ref.TransparencyMode=ptmPartial) and (Ref.Width>0),'character reference retains transparent pixels'); finally Ref.Free; end;
  var Width := W.ScriptDraft.Width; W.ScriptDraft.Width := Width+2; Rejected := False;
  try RequireSceneImageRequest(W.ScriptDraft,RigmThumbnailId,RequestId); except on E: Exception do Rejected := True; end;
  W.ScriptDraft.Width := Width; Check(Rejected,'changing video resolution rejects an old thumbnail request');
  var Title := JS(W.ScriptDraft.ScriptWizard,'titleInput'); PsdJson.Put(W.ScriptDraft.ScriptWizard,'titleInput',Title+'変更'); Rejected := False;
  try RequireSceneImageRequest(W.ScriptDraft,RigmThumbnailId,RequestId); except on E: Exception do Rejected := True; end;
  PsdJson.Put(W.ScriptDraft.ScriptWizard,'titleInput',Title); Check(Rejected,'changing manga title rejects an old thumbnail request');
  W.SaveScriptDraft(False); RequireSceneImageRequest(W.ScriptDraft,RigmThumbnailId,RequestId);
  Check(True,'pending thumbnail request survives saving source assets');
  var Path := TPath.Combine(Main.DataRoot,'Exchange\thumbnail.png'); ThumbPng(Path,clBlue);
  var A := TJSONObject.Create;
  try A.AddPair('sceneId',RigmThumbnailId); A.AddPair('requestId',RequestId); A.AddPair('path','Exchange\thumbnail.png');
    A.AddPair('sha256',THashSHA2.GetHashStringFromFile(Path)); A.AddPair('provenance','test-fixture'); W.DeliverScriptSceneImage(A);
  finally A.Free; end;
  Check(not ScriptScenesReady(W.ScriptDraft),'adopting a generated thumbnail still needs human confirmation');
  Frame.RefreshState; var Cues := TJSONArray.Create;
  try for var Cue in W.ScriptDraft.Cues do Cues.AddElement(Cue.Json);
    var Duration := W.ScriptDraft.Duration; Row.Approved.Checked := True; Row.Approved.OnClick(Row.Approved);
    RequireScriptThumbnail(W.ScriptDraft);
    var After := TJSONArray.Create;
    try for var Cue in W.ScriptDraft.Cues do After.AddElement(Cue.Json);
      Check((Cues.ToJSON=After.ToJSON) and (Abs(W.ScriptDraft.Duration-Duration-10)<0.000001),'human confirmation appends ten seconds and preserves every voice and cue');
    finally After.Free; end;
  finally Cues.Free; end;
  Check(ScriptScenesReady(W.ScriptDraft),'confirmed mandatory thumbnail completes stage 16');
  var Invalid := W.ScriptDraft.Json;
  try PsdJson.Put(JO(Invalid,'thumbnail'),'imagePrompt',TJSONNumber.Create(1)); Rejected := False;
    try var Bad := TRigmMovieProject.FromJson(Invalid); Bad.Free; except on E: ERigm do Rejected := True; end;
    Check(Rejected,'malformed thumbnail input raises a validation error without a double free');
  finally Invalid.Free; end;
  var Changed := W.ScriptDraft.Clone;
  try for var V in Changed.EndCards do if JS(TJSONObject(V),'kind')='thumbnail' then PsdJson.Put(TJSONObject(V),'transitionSeconds',TJSONNumber.Create(0));
    Rejected := False; try RequireScriptThumbnail(Changed); except on E: Exception do Rejected := True; end;
    Check(Rejected,'script export requires the smooth transition as well as the thumbnail image');
  finally Changed.Free; end;
  var Approval := W.ScriptDraft.Thumbnail.ImageApprovalKey; W.SaveScriptDraft(False); var Saved := LoadMovie(W.ScriptDraft.FileName);
  try RequireScriptThumbnail(Saved);
    Check(Saved.Thumbnail.ImageApproved and (Saved.Thumbnail.ImageApprovalKey=Approval),'save and reopen preserve thumbnail approval and content fingerprint');
    var Key := ThumbnailSourceKey(Saved); Saved.Scenes[0].Image := Path;
    Check((ThumbnailSourceKey(Saved)<>Key) and not ScriptSceneReady(Saved,Saved.Thumbnail),'changing a source image invalidates the existing thumbnail approval');
  finally Saved.Free; end;
  var Legacy := W.ScriptDraft.Clone;
  try Legacy.Thumbnail.Image := ''; Legacy.Thumbnail.ImageApproved := False; Legacy.Thumbnail.ImageApprovalKey := '';
    PrepareScriptThumbnail(Legacy); Check((Legacy.Thumbnail.Image<>'') and not Legacy.Thumbnail.ImageApproved,'legacy thumbnail is retained for human review without automatic approval');
  finally Legacy.Free; end;
  var Dialog := TRigmMovieEndingDialog.CreateForProject(nil,W.ScriptDraft);
  try var Draft := Dialog.Draft;
    try Check(JS(Draft,'thumbnailChoice')=JS(JO(JO(W.ScriptDraft.ScriptWizard,'closingData'),'draft'),'thumbnailChoice'),'movie ending controls preserve legacy fields and cannot opt out of the mandatory thumbnail');
    finally Draft.Free; end;
  finally Dialog.Free; end;
  Frame.RefreshState; W.SelectScriptScene(RigmThumbnailId);
  (Row.Parent as TScrollBox).VertScrollBar.Position := Row.Top; Capture('thumbnail-stage16');
  CheckThumbnailRendering;
end;
