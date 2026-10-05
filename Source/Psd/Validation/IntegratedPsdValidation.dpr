program IntegratedPsdValidation;
{$APPTYPE CONSOLE}

// 実素材の複製のみで一覧、編集分岐、保存往復、共通ジョブの短い出力を検証する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Forms, Vcl.Graphics, Vcl.ComCtrls, Vcl.StdCtrls,
  RIGMMakerMainForm, RigmEditorForm, PsdStudioForm, RigmStorage, RigmModel,
  RigmJson, RigmMovieModel, RigmMovieComposition, RigmMovieCompositionCommands,
  RigmMovieRendering, RigmMovieJobs, RigmCharacterCatalog, RigmMovieCompositor,
  RigmMovieCreator, RigmMovieForm;

var Passed: Integer; Root,OriginalPsd: string; Report: TJSONObject; Checks: TJSONArray;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create('FAIL: '+Message);
  Inc(Passed); Writeln('PASS: '+Message); Checks.Add(Message);
end;
procedure WaitJob(Job: TRigmMovieJob);
begin
  Job.Start; var Start := GetTickCount64;
  while not Job.Done do begin
    Application.ProcessMessages; Sleep(10);
    if GetTickCount64-Start>30000 then begin Job.Cancel; raise Exception.Create('Job timeout'); end;
  end;
  Job.WaitFor; var Status := Job.Status;
  try Check(JS(Status,'state')='succeeded','common '+Job.Kind+' job: '+Status.ToJSON);
  finally Status.Free; end;
end;
function SameBitmap(A,B: TBitmap): Boolean;
begin
  Result := (A<>nil) and (B<>nil) and (A.Width=B.Width) and (A.Height=B.Height);
  if not Result then Exit;
  A.PixelFormat := pf32bit; B.PixelFormat := pf32bit;
  for var Y := 0 to A.Height-1 do if not CompareMem(A.ScanLine[Y],B.ScanLine[Y],A.Width*4) then Exit(False);
end;
procedure VerifyMovie(const Format,Source: string);
begin
  var Project := TRigmMovieProject.Create;
  try
    Project.Title := Format+'形式の共通動画検証（無音0.2秒）';
    var Actor := TRigmMovieCharacter.Create;
    var ActorId := Actor.Id;
    try
      Actor.FileName := Source; Actor.RenderFormat := Format; Actor.X := 700; Actor.Y := 80;
      Actor.Width := 520; Actor.Height := 950; Actor.Name := '金髪アンドロイド';
      if Format='psd' then begin Actor.PsdView.AddPair('gaze','left-up'); Actor.PsdView.AddPair('motion','sway'); end;
      var Args := TJSONObject.Create;
      try Args.AddPair('character',Actor.Json); ApplyCompositionCommand(Project,'add-character',Args);
      finally Args.Free; end;
    finally Actor.Free; end;
    var C := Project.Character(ActorId);
    if Format='psd' then begin
      Check(C.Expressions.GetValue('happy')<>nil,'PSD expressions available to shared script');
      // 実在する視線名を使う（登録名は単一キャラ内の設定で管理）。
      var Asset := TPsdCharacterAsset.Create(Source);
      try
        var Gaze := JO(Asset.Character.Settings,'gaze');
        C.PsdView.RemovePair('gaze').Free;
        if Gaze.GetValue('left')<>nil then C.PsdView.AddPair('gaze','left') else C.PsdView.AddPair('gaze',Gaze.Pairs[0].JsonString.Value);
      finally Asset.Free; end;
    end;
    var Cue := TRigmMovieCue.Create; Cue.Text := ''; Cue.Subtitle := '同じ動画画面・字幕・出力経路';
    Cue.Pause := 0.2; Cue.Emotion := 'happy'; Cue.SpeakerId := C.SpeakerId; Project.Cues.Add(Cue);
    Project.Validate; ValidateCompositionMaterials(Project);
    var Directory := TPath.Combine(Root,'Comparison\'+Format); ForceDirectories(Directory);
    var Path := TPath.Combine(Directory,Format+'.rigmovie'); SaveMovie(Project,Path,True);
    var Loaded := LoadMovie(Path);
    try
      Check(Loaded.Characters[0].RenderFormat=Format,Format+' saved render format survives reopen');
      Check(Loaded.Cues[0].Subtitle=Cue.Subtitle,Format+' shared subtitle survives reopen');
      Check(Loaded.Characters[0].FileName.StartsWith('Characters\'),Format+' asset stored in Characters');
      if Format='psd' then Check(SameText(CharacterDataRoot(ResolveMoviePath(Loaded.FileName,Loaded.Characters[0].FileName)),Root),
        'saved PSD package uses configured data root work area');
      if Format='psd' then Check(JS(Loaded.Characters[0].PsdView,'motion')='sway','PSD view settings survive reopen');
      var PreviewPath := TPath.Combine(Directory,'preview.png');
      var Job := TRigmMovieJob.Create(Loaded,'preview',PreviewPath,0.1);
      try
        WaitJob(Job); var Actual := Job.TakeFrame; var Expected := RenderMovieFrame(Loaded,nil,0.1);
        try Check(SameBitmap(Actual,Expected),Format+' preview job equals shared renderer at identical time');
          Check((Actual.Width=1920) and (Actual.Height=1080),Format+' FullHD preview');
        finally Actual.Free; Expected.Free; end;
      finally Job.Free; end;
      var Video := TPath.Combine(Directory,'short.avi');
      Job := TRigmMovieJob.Create(Loaded,'export',Video,0);
      try WaitJob(Job); finally Job.Free; end;
      var Header := TFileStream.Create(Video,fmOpenRead or fmShareDenyNone);
      try
        var Magic: array[0..11] of AnsiChar; Header.ReadBuffer(Magic,SizeOf(Magic));
        Check((Magic[0]='R') and (Magic[1]='I') and (Magic[2]='F') and (Magic[3]='F') and
          (Magic[8]='A') and (Magic[9]='V') and (Magic[10]='I') and (Header.Size>10000),Format+' short MJPEG AVI written');
      finally Header.Free; end;
      if Format='psd' then begin
        var Asset := TPsdCharacterAsset.Create(Source);
        try
          var Poses := JA(Asset.Character.Settings,'nonFront');
          if Poses.Count>0 then begin
            C := Loaded.Characters[0]; C.PsdView.AddPair('nonFrontId',JS(TJSONObject(Poses[0]),'id'));
            var A := RenderMovieFrame(Loaded,nil,0.1); var B := RenderMovieFrame(Project,nil,0.1);
            try Check(not SameBitmap(A,B),'nonfront branch changes shared movie frame');
            finally A.Free; B.Free; end;
            SaveMovie(Loaded,TPath.Combine(Directory,'psd-nonfront.rigmovie'),True);
          end;
        finally Asset.Free; end;
      end;
    finally Loaded.Free; end;
  finally Project.Free; end;
end;
procedure Run;
begin
  Application.Initialize; Root := ExpandFileName(ParamStr(1)); OriginalPsd := ParamStr(2);
  var Main := TMainForm.Create(nil);
  try
    var Args := TJSONObject.Create; var LibraryJson: TJSONObject;
    try LibraryJson := Main.ExecuteWorkspace('library',Args); finally Args.Free; end;
    try
      var PsdPath,RigmPath: string; var PsdCount,RigmCount: Integer; PsdCount := 0; RigmCount := 0;
      for var V in JA(LibraryJson,'characters') do begin
        var E := TJSONObject(V); if JS(E,'path')='@sample' then Continue;
        if JS(E,'renderFormat')='psd' then begin Inc(PsdCount); PsdPath := JS(E,'path'); end
        else begin Inc(RigmCount); RigmPath := JS(E,'path'); end;
      end;
      Check((PsdCount=1) and (RigmCount=1),'same character listed twice with distinct formats');
      Report.AddPair('realCharacterLibrary',LibraryJson.Clone as TJSONValue);
      var List := TListView(Main.FindComponent('CharacterLibrary'));
      for var I := 0 to List.Items.Count-1 do
        if TRigmLibraryEntry(List.Items[I].Data).FileName=PsdPath then List.Items[I].Selected := True;
      Check((List.Selected<>nil) and List.Selected.Caption.Contains('[PSD]'),'library PSD format badge visible');
      List.OnDblClick(List);
      var Psd: TForm := nil;
      for var I := 0 to Main.ComponentCount-1 do if Main.Components[I] is TPsdStudioForm then Psd := TForm(Main.Components[I]);
      var Rigm := Main.OpenCharacterEditor(RigmPath);
      try
        Check(Psd is TPsdStudioForm,'PSD opens its dedicated editor'); Check(Rigm is TRigmEditorForm,'RIGM opens existing editor');
        var Document := LoadRigm(RigmPath);
        try
          Check(TPsdStudioForm(Psd).Session.Character.Id<>Document.FileId,'source character IDs differ');
          Check(TPsdStudioForm(Psd).Session.Character.Name=Document.Name,'PSD and RIGM are the same named real character');
          Check(SameText(JS(JO(TPsdStudioForm(Psd).Session.Character.Settings,'provenance'),'rigmSha256'),
            THashSHA2.GetHashStringFromFile(RigmPath)),'PSD provenance matches actual source RIGM hash');
        finally Document.Free; end;
        TPsdStudioForm(Psd).VerifyGuiFlow(TPath.Combine(Root,'gui-flow.json'));
        Check(FileExists(TPath.Combine(Root,'gui-flow.json')),'PSD GUI event/save/reopen flow completed');
      finally Psd.Free; Rigm.Free; end;
      TFile.Copy(OriginalPsd,PsdPath,True); // GUI試験の複製だけを原本の状態へ戻す。
      var Creation := TRigmMovieCreator(Main.FindComponent('MovieCreationPage'));
      var CreationList := TListView(Creation.FindComponent('CreationCharacters'));
      var Movie: TRigmMovieForm := nil;
      for var I := 0 to Main.ComponentCount-1 do if Main.Components[I] is TRigmMovieForm then Movie := TRigmMovieForm(Main.Components[I]);
      Check((CreationList.Items.Count=3) and (Movie<>nil),'shared creation lists real PSD and RIGM plus sample');
      var Item: TListItem := nil;
      for var I := 0 to CreationList.Items.Count-1 do
        if TCreationEntry(CreationList.Items[I].Data).FileName=PsdPath then Item := CreationList.Items[I];
      Check((Item<>nil) and Item.Caption.Contains('[PSD]'),'shared creation PSD format badge visible');
      Item.Selected := True; Item.Checked := True; Application.ProcessMessages;
      Check((Movie.Session.Project.Characters.Count=1) and (Movie.Session.Project.Characters[0].RenderFormat='psd'),
        'checking PSD in shared creation adds PSD actor');
      var Motion := TComboBox(Creation.FindComponent('CreationPsdMotion'));
      var Pose := TComboBox(Creation.FindComponent('CreationPsdPose'));
      Check(Motion.Enabled and Pose.Enabled,'PSD controls enabled for checked actor');
      Motion.ItemIndex := Motion.Items.IndexOf('breathe'); Motion.OnChange(Motion);
      Pose.ItemIndex := 1; Pose.OnChange(Pose);
      TButton(Creation.FindComponent('CreationApplyPsd')).Click;
      Check((JS(Movie.Session.Project.Characters[0].PsdView,'motion')='breathe') and
        (JS(Movie.Session.Project.Characters[0].PsdView,'nonFrontId')<>''),'shared creation applies breathing and registered pose');
      var Old := TRigmMovieCharacter.Create;
      try Old.FileName := RigmPath; var O := Old.Json;
        try O.RemovePair('renderFormat').Free; var Reopened := TRigmMovieCharacter.FromJson(O);
          try Check(Reopened.RenderFormat='rigm','older projects without renderFormat stay RIGM'); finally Reopened.Free; end;
        finally O.Free; end;
      finally Old.Free; end;
      VerifyMovie('psd',PsdPath); VerifyMovie('rigm',RigmPath);
    finally LibraryJson.Free; end;
  finally Main.Free; end;
end;
begin
  Report := TJSONObject.Create; Checks := TJSONArray.Create; Report.AddPair('checks',Checks);
  try
    try Run; Report.AddPair('passed',TJSONNumber.Create(Passed)); Report.AddPair('realSpeechVerified',TJSONBool.Create(False));
      TFile.WriteAllText(TPath.Combine(Root,'integration-result.json'),Report.ToJSON,TEncoding.UTF8);
      Writeln('TOTAL: '+Passed.ToString);
    except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  finally Report.Free; end;
end.
