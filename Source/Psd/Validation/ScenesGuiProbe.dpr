program ScenesGuiProbe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.Classes, System.Types, System.IOUtils, System.JSON,
  System.Math, System.Hash, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage,
  RigmWizardWorkspace, RigmScriptScenesFrame, RigmMovieModel, RigmMovieComposition,
  RigmScriptTextModel, RigmScriptReviewModel, RigmScriptCastingModel, RigmScriptScenesModel,
  RigmMovieLayout, RigmMovieImageTransfer, RigmMovieCompositor, RigmMovieAudio, RigmMoviePreparation,
  RigmJson, PsdJson;
{$R *.res}
type
  TProbeHost = class
    Form: TForm;
    Workspace: TRigmWizardWorkspace;
    Frame: TRigmScriptScenesFrame;
    procedure Changed(Sender: TObject);
    procedure GuiException(Sender: TObject; E: Exception);
  end;
var
  Host: TProbeHost;
  Checks: TJSONArray;
  Root,FixtureRoot,SourceImage,SourceHash,TextHash,Error: string;
  DialogueOnly: Boolean;
procedure Check(Value: Boolean; const Name: string);
begin
  if not Value then begin
    if (Host<>nil) and (Host.Frame<>nil) then begin
      var Guide := Host.Frame.FindComponent('ScriptSceneGuide') as TLabel;
      if Guide<>nil then Writeln('STATUS ',Guide.Caption);
    end;
    raise Exception.Create(Name);
  end;
  Checks.Add(Name); Writeln('PASS ',Name);
end;
procedure Pump(Milliseconds: Cardinal);
begin
  var UntilTime := GetTickCount64+Milliseconds;
  repeat Application.ProcessMessages; Sleep(5); if Error<>'' then raise Exception.Create(Error);
  until GetTickCount64>=UntilTime;
end;
procedure TProbeHost.Changed(Sender: TObject);
begin if Frame<>nil then Frame.RefreshState; end;
procedure TProbeHost.GuiException(Sender: TObject; E: Exception);
begin Error := E.ClassName+': '+E.Message; end;
function Row(Index: Integer): TRigmSceneImageRow;
begin
  Result := nil; var Id := Host.Workspace.ScriptDraft.Scenes[Index].Id;
  for var I := 0 to Host.Frame.ComponentCount-1 do
    if (Host.Frame.Components[I] is TRigmSceneImageRow) and
      (TRigmSceneImageRow(Host.Frame.Components[I]).SceneId=Id) then
      Exit(TRigmSceneImageRow(Host.Frame.Components[I]));
  raise Exception.Create('Missing scene row');
end;
procedure Capture(const Name: string);
begin
  var Bitmap := TBitmap.Create; var Png := TPngImage.Create;
  try
    Bitmap.SetSize(Host.Frame.Width,Host.Frame.Height); Host.Frame.PaintTo(Bitmap.Canvas,0,0);
    Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,Name+'.png'));
  finally Png.Free; Bitmap.Free; end;
end;
procedure Prepare;
begin
  Host.Workspace.StartPipe(FixtureRoot); Host.Workspace.NewScriptDraft;
  var P := Host.Workspace.ScriptDraft; P.Speaker('narrator').VoiceUuid := 'owned'; P.Speaker('narrator').StyleId := 0;
  PrepareScriptText(P); var Body := '';
  for var I := 0 to 39 do begin
    var S := TRigmMovieScene.Create; S.Title := 'シーン '+(I+1).ToString; P.Scenes.Add(S);
    var C := TRigmMovieCue.Create; C.Scene := S.Id; C.Text := '検証用のセリフ '+(I+1).ToString;
    C.Subtitle := C.Text; P.Cues.Add(C); if I>0 then Body := Body+#13#10; Body := Body+C.Text;
  end;
  if DialogueOnly then begin
    P.Cues[0].Text := '山へ向かう。'+#13#10+'雪が降ってきた。'+#10+'道が白い。'+#13+'山頂を目指す。';
    var C := TRigmMovieCue.Create; C.Scene := P.Scenes[0].Id;
    C.Text := '次のセリフ。'+#13#10+'山小屋が見えた。'; C.Subtitle := C.Text; P.Cues.Add(C);
    Body := '';
    for var Cue in P.Cues do begin if Body<>'' then Body := Body+#13#10; Body := Body+Cue.Text; end;
  end;
  PsdJson.Put(ScriptSection(P,'body'),'text',Body);
  var Cast := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptCasting","schemaVersion":1,"state":"ready","requestId":"owned","roles":[],"rows":[]}');
  PsdJson.Put(P.ScriptWizard,'casting',Cast); Cast.AddPair('selectedCue',P.Cues[0].Id);
  var Role := TJSONObject.Create; JA(Cast,'roles').AddElement(Role);
  AddN(Role,'number',1); Role.AddPair('path','RIGM\\fixture.rigm'); Role.AddPair('speakerId','narrator'); AddB(Role,'active',True);
  var Offset := 0;
  for var C in P.Cues do begin
    var R := TJSONObject.Create; JA(Cast,'rows').AddElement(R); R.AddPair('cueId',C.Id); R.AddPair('section','body');
    AddN(R,'offset',Offset); AddN(R,'length',Length(C.Text)); AddN(R,'role',1); AddB(R,'confirmed',True); R.AddPair('origin','human');
    Inc(Offset,Length(C.Text)+2);
  end;
  Cast.AddPair('sourceFingerprint',ScriptFingerprint(P)); Cast.AddPair('fingerprint',CastingFingerprint(P));
  P.Layout := 'theme'; P.LDirection := 'right'; P.BackgroundColor := LayoutBackgroundColor('dark');
  PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'layoutStatus','complete');
  PsdJson.Put(P.ScriptWizard,'backgroundTone','dark');
  PsdJson.Put(P.ScriptWizard,'castingStatus','complete'); PsdJson.Put(P.ScriptWizard,'voiceStatus','complete');
  PsdJson.Put(P.ScriptWizard,'stage','scenes'); PsdJson.Put(P.ScriptWizard,'furthestStage','scenes');
  PsdJson.Put(P.ScriptWizard,'titleInput','シーン一覧検証'); PsdJson.Put(P.ScriptWizard,'titleStatus','complete');
  PsdJson.Put(P.ScriptWizard,'scene-assignmentStatus','complete');
  PrepareScriptScenes(P,False); P.Scenes[0].ImagePrompt := '雪山の景色'; P.Scenes[0].Description := '雪山の補足';
  P.Scenes[1].ImagePrompt := '元の画像要望'; P.Scenes[1].ImageFeedback := '背景を明るく';
  P.Scenes[2].Description := '補足のみ';
  P.Changed; Host.Workspace.SaveScriptDraft;
  Host.Workspace.OpenScriptDraft(P.FileName); P := Host.Workspace.ScriptDraft;
  Check(Host.Workspace.CurrentScriptStage='scenes','owned fixture resumes at image stage'); TextHash := ScriptFingerprint(P);
  SourceImage := TPath.Combine(FixtureRoot,'Exchange\fixture.png');
  var Image := TPngImage.CreateBlank(COLOR_RGB,8,128,72);
  try
    Image.Canvas.Brush.Color := clNavy; Image.Canvas.FillRect(Rect(0,0,128,72));
    Image.Canvas.Brush.Color := clAqua; Image.Canvas.Rectangle(18,16,104,56); Image.SaveToFile(SourceImage);
  finally Image.Free; end;
  SourceHash := THashSHA2.GetHashStringFromFile(SourceImage);
end;
procedure CheckDialogue;
begin
  var P := Host.Workspace.ScriptDraft; var CueText := P.Cues[0].Text; var LastCueText := P.Cues.Last.Text;
  var Reference := Host.Frame.FindComponent('ScriptSceneDialogueText') as TEdit;
  var Panel := Host.Frame.FindComponent('ScriptSceneDialogue') as TPanel;
  Check((Reference<>nil) and Reference.ReadOnly and not Reference.TabStop,'dialogue reference is read-only and outside input tab order');
  var FirstRow := Row(0); FirstRow.Prompt.SetFocus; Pump(20);
  Check(Reference.Text='山へ向かう。 雪が降ってきた。 道が白い。 山頂を目指す。 次のセリフ。 山小屋が見えた。','scene dialogue joins matching cues in order and converts CRLF/LF/CR to spaces');
  var Value: string := Reference.Text;
  Check(not Value.Contains(#13) and not Value.Contains(#10) and not Value.Contains('検証用のセリフ 2'),'single-line reference excludes other scenes');
  var SecondRow := Row(1); SecondRow.Description.SetFocus; Pump(20);
  Check(Reference.Text='検証用のセリフ 2','caption focus switches dialogue to that scene');
  FirstRow.Position.SetFocus; Pump(20);
  Check(Reference.Text=Value,'position focus switches dialogue back');
  FirstRow.Prompt.SetFocus; FirstRow.Prompt.Text := '画像を考えながら入力'; FirstRow.Prompt.SelStart := 4;
  Host.Frame.RefreshState; Pump(20);
  Check((FirstRow.Prompt.Text='画像を考えながら入力') and (FirstRow.Prompt.SelStart=4) and FirstRow.Prompt.Focused,'dialogue refresh retains input and focus');
  Check(Reference.Text=Value,'dialogue remains available while typing');
  Check(Host.Frame.RequestFinish,'image instruction input commits with dialogue visible');
  Reference.SelStart := 6; Reference.SelLength := 4; Host.Frame.RefreshState;
  Check((Reference.SelStart=6) and (Reference.SelLength=4),'unchanged refresh preserves reference selection');
  var Scroll := Host.Frame.FindComponent('ScriptSceneRows') as TScrollBox; var Top := Panel.Top;
  Scroll.VertScrollBar.Position := Scroll.VertScrollBar.Range; Pump(20);
  Check((Panel.Top=Top) and (Panel.Top>=Scroll.Top+Scroll.Height),'reference stays below the scrolling rows');
  Scroll.VertScrollBar.Position := 0;
  Check((P.Cues[0].Text=CueText) and (P.Cues.Last.Text=LastCueText) and (ScriptFingerprint(P)=TextHash),'display conversion preserves original cue text and manuscript');
  Capture('scene-dialogue-reference');
end;
procedure CheckInputs;
begin
  var Rows: TArray<TRigmSceneImageRow>; SetLength(Rows,40);
  for var I := 0 to 39 do Rows[I] := Row(I);
  var LegacyText: string := Rows[1].Prompt.Text;
  Check(LegacyText.Contains('元の画像要望') and LegacyText.Contains('背景を明るく'),'legacy prompt and correction share one memo');
  Rows[1].Prompt.Text := Rows[1].Prompt.Text+#13#10+'山頂を追加';
  Check(Host.Frame.RequestFinish,'all row inputs publish');
  var P := Host.Workspace.ScriptDraft;
  Check(P.Scenes[0].DisplayMode='both','prompt and caption show both');
  Check(P.Scenes[1].DisplayMode='image','prompt alone shows image');
  Check(P.Scenes[2].DisplayMode='text','caption alone shows text');
  Check(P.Scenes[3].DisplayMode='none','empty inputs show neither');
  Check(P.Scenes[1].ImageFeedback='','edited unified instructions remove separate feedback');
  Rows[0].Approved.Checked := True; Pump(20);
  Check(not P.Scenes[0].ImageApproved,'image row cannot confirm before image arrives');
  Rows[2].Approved.Checked := True; Rows[3].Approved.Checked := True; Pump(20);
  Check(ScriptSceneReady(P,P.Scenes[2]) and ScriptSceneReady(P,P.Scenes[3]),'caption-only and empty rows confirm without image');
  Check(Rows[2].Prompt.ReadOnly and Rows[2].Description.ReadOnly and not Rows[2].Position.Enabled,'confirmed inputs lock');
  Rows[2].Approved.Checked := False;
  Check(not P.Scenes[2].ImageApproved and not Rows[2].Description.ReadOnly,'uncheck unlocks inputs');
  for var I := 0 to 4 do begin
    Rows[2].Position.ItemIndex := I; Rows[2].Position.OnChange(Rows[2].Position);
    Check(Host.Frame.RequestFinish,'position input commits '+I.ToString);
    var Position := P.Scenes[2].DescriptionPosition;
    var Region := MovieDescriptionRegion('theme','right',Position);
    Check(not Region.IsEmpty and (Region.Top>=0) and (Region.Bottom<0.79),'caption region stays above subtitles '+I.ToString);
  end;
  Host.Workspace.SaveScriptDraft; var Saved := P.FileName;
  Host.Workspace.OpenScriptDraft(Saved); Pump(30); P := Host.Workspace.ScriptDraft;
  Check((P.Scenes[2].DescriptionPosition='screen-top') and P.Scenes[3].ImageApproved,'position and image-free approval survive reopen');
  var OriginalRow := Rows[10]; var OriginalText := Rows[10].Prompt.Text;
  Rows[10].Prompt.Text := '入力途中'; Rows[10].Prompt.SelStart := 2;
  Host.Frame.RefreshState;
  Check((Rows[10]=OriginalRow) and (Rows[10].Prompt.Text='入力途中') and (Rows[10].Prompt.SelStart=2),'refresh retains row and editing cursor');
  Rows[10].Prompt.Text := OriginalText; Check(Host.Frame.RequestFinish,'pending draft completes');
end;
procedure CheckLayout;
begin
  for var PPI in [96,144,192,96] do begin
    Host.Form.Scaled := True; Host.Form.ScaleForPPI(PPI); Host.Form.Scaled := False;
    for var Size in [0,1] do begin
      Host.Form.ClientWidth := MulDiv(IfThen(Size=0,1280,800),PPI,96);
      Host.Form.ClientHeight := MulDiv(IfThen(Size=0,720,520),PPI,96);
      Host.Form.Realign; Pump(40);
      var Scroll := Host.Frame.FindComponent('ScriptSceneRows') as TScrollBox;
      Scroll.VertScrollBar.Position := 0;
      Check(Row(0).Height=MulDiv(88,PPI,96),'compact row height '+PPI.ToString+'/'+Size.ToString);
      Check(Scroll.ClientHeight div Row(0).Height>=4,'at least four visible rows '+PPI.ToString+'/'+Size.ToString);
      for var I := 0 to 39 do begin
        var R := Row(I);
        Check((R.Prompt.Left+R.Prompt.Width<R.Description.Left) and
          (R.Description.Left+R.Description.Width<R.Picture.Left),'columns never overlap '+PPI.ToString+'/'+I.ToString);
        Check((R.Description.Top+R.Description.Height<R.Position.Top) and
          (R.Picture.Top+R.Picture.Height<R.Approved.Top),'position and confirmation fit below content '+PPI.ToString+'/'+I.ToString);
      end;
      Scroll.VertScrollBar.Position := Scroll.VertScrollBar.Range;
      Check(Row(39).Top+Row(39).Height<=Scroll.ClientHeight+1,'last scene reachable '+PPI.ToString+'/'+Size.ToString);
      var OldPos := Scroll.VertScrollBar.Position; Host.Frame.RefreshState;
      Check(Scroll.VertScrollBar.Position=OldPos,'refresh preserves scroll '+PPI.ToString+'/'+Size.ToString);
      Scroll.VertScrollBar.Position := 0;
      if Size=0 then Capture('scene-layout-'+PPI.ToString);
    end;
  end;
end;
procedure CheckRendering;
begin
  var P := TRigmMovieProject.Create;
  try
    P.Width := 640; P.Height := 360; P.BackgroundColor := clBlack; P.ThemeBackground := '';
    var S := TRigmMovieScene.Create; S.Title := ''; S.Image := SourceImage; S.Description := '補足'; S.Padding := 1;
    P.Scenes.Add(S);
    for var Mode in ['none','image','text','both'] do begin
      S.DisplayMode := Mode; S.DescriptionPosition := 'below-image';
      var B := RenderComposition(P,0.05,nil);
      try
        var R := ScaleLayoutRect(MovieDescriptionRegion(P.Layout,P.LDirection,S.DescriptionPosition),640,360);
        var TextVisible := ColorToRGB(B.Canvas.Pixels[R.Left+2,R.Top+2])=ColorToRGB($00302820);
        Check(TextVisible=((Mode='text') or (Mode='both')),'compositor honors caption visibility '+Mode);
        var ImageRect := ScaleLayoutRect(MovieLayoutRegions(P.Layout,P.LDirection).Image,640,360);
        var ImageVisible := ColorToRGB(B.Canvas.Pixels[(ImageRect.Left+ImageRect.Right) div 2,(ImageRect.Top+ImageRect.Bottom) div 2])=ColorToRGB(clAqua);
        Check(ImageVisible=((Mode='image') or (Mode='both')),'compositor honors image visibility '+Mode);
      finally B.Free; end;
    end;
    S.Image := TPath.Combine(Root,'absent-image.png'); var PreviousKey := '';
    for var Mode in ['none','image','text','both'] do begin
      S.DisplayMode := Mode; var Missing := False;
      try ValidateCompositionMaterials(P); except on E: Exception do Missing := E.Message.Contains('Scene image is missing'); end;
      Check(Missing=((Mode='image') or (Mode='both')),'material validation ignores hidden images '+Mode);
      var Diagnostics := TJSONObject.Create; var Job := TJSONObject.Create;
      try
        var Preparation := MoviePreparation(P,Diagnostics,Job);
        try
          var HasIssue := False;
          for var Value in JA(Preparation,'issues') do HasIssue := HasIssue or (JS(TJSONObject(Value),'code')='scene_image_missing');
          Check(HasIssue=Missing,'export preparation agrees with displayed image '+Mode);
        finally Preparation.Free; end;
      finally Job.Free; Diagnostics.Free; end;
      var CurrentKey := MoviePreparationKey(P);
      if PreviousKey<>'' then Check(CurrentKey<>PreviousKey,'mode change invalidates material diagnostics '+Mode);
      PreviousKey := CurrentKey;
    end;
    S.Image := SourceImage; S.DisplayMode := 'text';
    for var Position in ['below-image','image-top','image-center','image-bottom','screen-top'] do begin
      S.DescriptionPosition := Position;
      var B := RenderComposition(P,0.05,nil);
      try
        var R := ScaleLayoutRect(MovieDescriptionRegion(P.Layout,P.LDirection,Position),640,360);
        Check(ColorToRGB(B.Canvas.Pixels[R.Left+2,R.Top+2])=ColorToRGB($00302820),'saved position reaches compositor '+Position);
        var Png := TPngImage.Create;
        try Png.Assign(B); Png.SaveToFile(TPath.Combine(Root,'caption-'+Position+'.png')); finally Png.Free; end;
      finally B.Free; end;
    end;
  finally P.Free; end;
end;
begin
  SetTextCodePage(System.Output,CP_UTF8); Checks := TJSONArray.Create; Host := TProbeHost.Create;
  try
    try
      Root := TPath.GetFullPath(ParamStr(1));
      if not Root.StartsWith(IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ExtractFileDir(ParamStr(0)),'..'))),True) then
        raise Exception.Create('Use output under isolated probe folder');
      ForceDirectories(Root); FixtureRoot := TPath.Combine(Root,'fixture'); ForceDirectories(FixtureRoot);
      ForceDirectories(TPath.Combine(Root,'settings')); SetEnvironmentVariable('RIGMMAKER_SETTINGS_DIR',PChar(TPath.Combine(Root,'settings')));
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
      Application.Initialize; Application.MainFormOnTaskbar := False; Application.OnException := Host.GuiException;
      Check(TStyleManager.TrySetStyle('Windows Modern Dark'),'production style loaded');
      Host.Form := TForm.CreateScaledNew(nil,96); Host.Form.Scaled := False;
      Host.Form.Font.PixelsPerInch := 96; Host.Form.Font.IsDPIRelated := True;
      Host.Form.Font.Name := 'Yu Gothic UI'; Host.Form.Font.Size := 10;
      Host.Form.ClientWidth := 1280; Host.Form.ClientHeight := 720;
      DialogueOnly := ParamStr(2)='/dialogue-only';
      Host.Workspace := TRigmWizardWorkspace.Create(nil); Prepare;
      Host.Frame := TRigmScriptScenesFrame.CreateForWorkspace(Host.Form,Host.Workspace);
      Host.Workspace.OnScriptChanged := Host.Changed;
      ShowWindow(Host.Form.Handle,SW_SHOWNOACTIVATE); Host.Form.Visible := True; Host.Frame.RefreshState; Pump(60);
      if DialogueOnly then begin CheckDialogue; CheckLayout; end
      else begin
      CheckInputs; CheckLayout; CheckRendering;
      var Info := Host.Workspace.Pipe.Info;
      try Info.AddPair('imagePath',SourceImage); Info.AddPair('imageHash',SourceHash);
        TFile.WriteAllText(TPath.Combine(Root,'ready-for-pipe.json'),Info.ToJSON,TEncoding.UTF8);
      finally Info.Free; end;
      var Deadline := GetTickCount64+30000;
      while not FileExists(TPath.Combine(Root,'pipe-done.json')) and (GetTickCount64<Deadline) do Pump(20);
      Check(FileExists(TPath.Combine(Root,'pipe-done.json')),'external request test completed');
      var P := Host.Workspace.ScriptDraft;
      Check((P.Scenes[0].Image<>'') and not P.Scenes[0].ImageApproved,'pipe adopts requested image and awaits human confirmation');
      var FirstRow := Row(0);
      Check((FirstRow.Picture.Picture.Width>0) and (FirstRow.ImageStamp<>''),'pipe change notification refreshes the matching image row');
      FirstRow.Approved.Checked := True; Pump(30); Check(ScriptSceneReady(P,P.Scenes[0],True),'delivered image can confirm');
      Capture('scene-with-requested-image');
      Check(THashSHA2.GetHashStringFromFile(SourceImage)=SourceHash,'source image unchanged');
      Check(ScriptFingerprint(P)=TextHash,'manuscript unchanged');
      end;
    except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln('FAIL ',Error); ExitCode := 1; end; end;
    var Report := TJSONObject.Create;
    try Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('error',Error);
      TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
    finally Report.Free; end;
    Writeln('Checks=',Checks.Count);
  finally
    Application.OnException := nil;
    if Host.Workspace<>nil then Host.Workspace.OnScriptChanged := nil;
    Host.Frame.Free; Host.Workspace.Free; Host.Form.Free; Host.Free; Checks.Free;
  end;
end.
