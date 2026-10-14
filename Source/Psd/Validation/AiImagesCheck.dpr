program AiImagesCheck;
{$APPTYPE CONSOLE}
// 隔離した架空作品。protocol fixtureと、--live時の本物の画像生成を明確に区別する。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.NetEncoding,
  Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Imaging.pngimage, RigmWizardWorkspace, RigmScriptScenesFrame, RigmMovieModel,
  RigmScriptScenesModel, RigmScriptAiImages, RigmScriptTextModel, RigmScriptCastingModel, RigmScriptReviewModel, RigmMovieComposition,
  RigmMovieImageTransfer, RigmMovieLayout, RigmModel, RigmSample, RigmStorage, RigmJson, PsdJson;
{$R *.res}
type
  TObserver = class
    Frame: TRigmScriptScenesFrame;
    Error: string;
    procedure Changed(Sender: TObject);
    procedure ExceptionRaised(Sender: TObject; E: Exception);
  end;
var W: TRigmWizardWorkspace; Host: TForm; Frame: TRigmScriptScenesFrame; Observer: TObserver;
  Root,FixtureImage,FixtureMode,PreviousExe: string; Checks: TJSONArray;
procedure TObserver.Changed(Sender: TObject);
begin if Frame<>nil then Frame.RefreshState; end;
procedure TObserver.ExceptionRaised(Sender: TObject; E: Exception);
begin Error := E.ClassName+': '+E.Message; end;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); Checks.Add(Name); Writeln('PASS ',Name); end;
procedure Pump(Milliseconds: Cardinal);
begin
  var Deadline := GetTickCount64+Milliseconds;
  repeat Application.ProcessMessages; Sleep(5); if Observer.Error<>'' then raise Exception.Create(Observer.Error);
  until GetTickCount64>=Deadline;
end;
function LiveRequested: Boolean;
begin Result := False; for var I := 1 to ParamCount do if ParamStr(I)='--live' then Exit(True); end;
function Row(const Id: string): TRigmSceneImageRow;
begin
  Result := nil;
  for var I := 0 to Frame.ComponentCount-1 do if (Frame.Components[I] is TRigmSceneImageRow) and
    (TRigmSceneImageRow(Frame.Components[I]).SceneId=Id) then Exit(TRigmSceneImageRow(Frame.Components[I]));
  raise Exception.Create('Missing image row');
end;
function Button(const Name: string): TButton;
begin Result := Frame.FindComponent(Name) as TButton; end;
procedure WaitDone(Timeout: Cardinal=15000);
begin
  var Deadline := GetTickCount64+Timeout;
  while W.SceneImageAiBusy do begin Pump(30); if GetTickCount64>Deadline then raise Exception.Create('Image job timeout: '+W.SceneImageAiMessage); end;
end;
procedure Select(const Id: string);
begin W.SelectScriptScene(Id); Frame.RefreshState; end;
function CueContent: string;
begin
  var A := TJSONArray.Create;
  try for var C in W.ScriptDraft.Cues do A.AddElement(C.Json); Result := A.ToJSON; finally A.Free; end;
end;
procedure Mode(const Value: string);
begin Winapi.Windows.SetEnvironmentVariable('RIGM_TEST_IMAGE_MODE',PChar(Value)); end;
procedure ProtocolFixture;
  procedure Reply(Id: TJSONValue; Value: TJSONObject);
  begin
    var R := TJSONObject.Create.AddPair('id',Id.Clone as TJSONValue).AddPair('result',Value);
    try Writeln(R.ToJSON); Flush(Output); finally R.Free; end;
  end;
  procedure Event(const Method: string; Payload: TJSONObject);
  begin
    var R := TJSONObject.Create.AddPair('method',Method).AddPair('params',Payload);
    try Writeln(R.ToJSON); Flush(Output); finally R.Free; end;
  end;
begin
  while not Eof(Input) do begin
    var Line: string; Readln(Line); var V := TJSONObject.ParseJSONValue(Line) as TJSONObject;
    try
      var Method := JS(V,'method'); var Id := V.GetValue('id'); if Id=nil then Continue;
      if Method='initialize' then Reply(Id,TJSONObject.Create)
      else if Method='thread/start' then Reply(Id,TJSONObject.Create.AddPair('thread',TJSONObject.Create.AddPair('id','owned-protocol-fixture')))
      else if Method='turn/start' then begin
        Reply(Id,TJSONObject.Create.AddPair('turn',TJSONObject.Create.AddPair('id','owned-turn')));
        var TestMode := GetEnvironmentVariable('RIGM_TEST_IMAGE_MODE');
        if TestMode='delay' then Sleep(10000) else Sleep(300);
        if TestMode<>'no-image' then begin
          var Item := TJSONObject.Create.AddPair('type','imageGeneration').AddPair('id','owned-image').AddPair('status','completed');
          if TestMode='failure' then PsdJson.Put(Item,'status','failed')
          else if TestMode='base64' then Item.AddPair('result',TNetEncoding.Base64.EncodeBytesToString(TFile.ReadAllBytes(GetEnvironmentVariable('RIGM_TEST_IMAGE_PATH'))))
          else Item.AddPair('savedPath',GetEnvironmentVariable('RIGM_TEST_IMAGE_PATH'));
          Event('item/completed',TJSONObject.Create.AddPair('threadId','owned-protocol-fixture').AddPair('turnId','owned-turn').AddPair('item',Item));
        end;
        Event('item/completed',TJSONObject.Create.AddPair('threadId','owned-protocol-fixture').AddPair('turnId','owned-turn')
          .AddPair('item',TJSONObject.Create.AddPair('type','agentMessage').AddPair('phase','final_answer').AddPair('text','owned protocol fixture')));
        Event('turn/completed',TJSONObject.Create.AddPair('threadId','owned-protocol-fixture')
          .AddPair('turn',TJSONObject.Create.AddPair('id','owned-turn').AddPair('status','completed')));
      end;
    finally V.Free; end;
  end;
end;
procedure Prepare;
begin
  W := TRigmWizardWorkspace.Create(nil); W.StartPipe(TPath.Combine(Root,'OwnedData')); W.NewScriptDraft;
  W.SetScriptTitle('海辺の図書館・架空検証'); var P := W.ScriptDraft; PrepareScriptText(P);
  P.Speaker('narrator').VoiceUuid := 'owned'; P.Speaker('narrator').StyleId := 0;
  var CharacterPath := W.Pipe.Workspace.Resolve('RIGM\fixture.rigm',False); ForceDirectories(ExtractFilePath(CharacterPath));
  var Character := TRigmDocument.Create;
  try PopulateRigmSample(Character); Character.Usable := True; SaveRigm(Character,CharacterPath); finally Character.Free; end;
  JA(P.ScriptWizard,'selectedCharacters').AddElement(TJSONObject.Create.AddPair('path','RIGM\fixture.rigm').AddPair('name','所有サンプルキャラ').AddPair('renderFormat','rigm'));
  var Cast := PsdJson.ObjectText('{"format":"RIGMMaker.ScriptCasting","schemaVersion":1,"state":"ready","requestId":"owned","roles":[],"rows":[]}');
  PsdJson.Put(P.ScriptWizard,'casting',Cast);
  var Role := TJSONObject.Create; JA(Cast,'roles').AddElement(Role); AddN(Role,'number',1);
  Role.AddPair('path','RIGM\fixture.rigm'); Role.AddPair('speakerId','narrator'); AddB(Role,'active',True);
  var Body := '';
  for var I := 0 to 1 do begin
    var S := TRigmMovieScene.Create; S.Title := 'シーン'+(I+1).ToString; P.Scenes.Add(S);
    var C := TRigmMovieCue.Create; C.Scene := S.Id; C.Text := '海辺の小さな図書館を紹介します。';
    if I=1 then C.Text := '同じ図書館の入口へ歩いてきました。';
    C.Subtitle := C.Text; C.VoiceReading := C.Text; P.Cues.Add(C);
    var R := TJSONObject.Create; JA(Cast,'rows').AddElement(R); R.AddPair('cueId',C.Id); R.AddPair('section','body');
    AddN(R,'offset',Length(Body)); AddN(R,'length',Length(C.Text)); AddN(R,'role',1); AddB(R,'confirmed',True); R.AddPair('origin','human');
    if Body<>'' then Body := Body+#13#10; Body := Body+C.Text;
    C.AudioKey := P.AudioFingerprint(C); C.VoiceHeardKey := C.AudioKey;
  end;
  PsdJson.Put(ScriptSection(P,'body'),'text',Body); Cast.AddPair('selectedCue',P.Cues[0].Id);
  Cast.AddPair('sourceFingerprint',ScriptFingerprint(P)); Cast.AddPair('fingerprint',CastingFingerprint(P));
  P.Layout := 'theme'; P.LDirection := 'right'; P.BackgroundColor := LayoutBackgroundColor('dark');
  PsdJson.Put(P.ScriptWizard,'layoutChoice','theme'); PsdJson.Put(P.ScriptWizard,'layoutStatus','complete');
  PsdJson.Put(P.ScriptWizard,'backgroundTone','dark');
  for var Key in ['castingStatus','voiceStatus','scene-assignmentStatus'] do PsdJson.Put(P.ScriptWizard,Key,'complete');
  PsdJson.Put(P.ScriptWizard,'stage','scenes'); PsdJson.Put(P.ScriptWizard,'furthestStage','scenes');
  PrepareScriptScenes(P,False);
  P.Scenes[0].ImagePrompt := '青い空と海辺の小さな図書館。絵本風のイラスト。文字は入れない。';
  P.Scenes[1].ImagePrompt := '同じ海辺の小さな図書館の入口へ近づいた場面。前の画像と同じ建物と画風。文字は入れない。';
  W.SaveScriptDraft; W.OpenScriptDraft(P.FileName); P := W.ScriptDraft;
  FixtureImage := W.Pipe.Workspace.Resolve('Exchange\fixture.png',False); ForceDirectories(ExtractFilePath(FixtureImage));
  var Image := TPngImage.CreateBlank(COLOR_RGB,8,128,72);
  try Image.Canvas.Brush.Color := clNavy; Image.Canvas.FillRect(Rect(0,0,128,72));
    Image.Canvas.Brush.Color := clAqua; Image.Canvas.Rectangle(18,16,104,56); Image.SaveToFile(FixtureImage);
  finally Image.Free; end;
  Host := TForm.CreateNew(nil); Host.SetBounds(40,40,1280,820); Host.Caption := 'AI画像の所有fixture';
  Frame := TRigmScriptScenesFrame.CreateForWorkspace(Host,W); Frame.Parent := Host;
  Observer := TObserver.Create; Observer.Frame := Frame; W.OnScriptChanged := Observer.Changed;
  Application.OnException := Observer.ExceptionRaised; Host.Show; Frame.RefreshState; Pump(100);
  Select(P.Scenes[0].Id);
  Check(Button('ScriptSceneAiSelected').Showing and Button('ScriptSceneAiAll').Showing,'full text image generation buttons are visible');
  Check((Frame.FindComponent('ScriptSceneAiStatus') as TLabel).Width>400,'image status has usable width');
end;
procedure ModelChecks;
begin
  var P := W.ScriptDraft; var Q := SceneImageAiTargets(P,'');
  try
    Check((Q.Count=2) and (JS(TJSONObject(Q[0]),'sceneId')=P.Scenes[0].Id) and
      (JS(TJSONObject(Q[1]),'sceneId')=P.Scenes[1].Id),'batch follows fixed scene order and skips empty background and premature thumbnail');
  finally Q.Free; end;
  P.CommonBackground.ImagePrompt := '共通の青空';
  Q := SceneImageAiTargets(P,'');
  try Check((Q.Count=3) and (JS(TJSONObject(Q[0]),'sceneId')=RigmCommonBackgroundId),'optional background is generated first when requested'); finally Q.Free; end;
  P.CommonBackground.ImagePrompt := '';
  var Rejected := False;
  try Q := SceneImageAiTargets(P,RigmThumbnailId); Q.Free; except on E: Exception do Rejected := True; end;
  Check(Rejected,'thumbnail waits for human approval of source images');
  var Request := RigmScriptScenesModel.RequestScriptSceneImage(P,P.Scenes[0].Id); var Refs := TJSONArray.Create;
  try
    var Prompt := SceneImageAiPrompt(P,Request,Refs);
    var Context := TJSONObject.ParseJSONValue(Copy(Prompt,Pos('画像データ: ',Prompt)+Length('画像データ: '),MaxInt)) as TJSONObject;
    try Check((JS(TJSONObject(JA(Context,'sourceCues')[0]),'text')=P.Cues[0].Text) and
      (JS(JO(Context,'imageRequest'),'prompt')=P.Scenes[0].ImagePrompt) and (Pos('sizeInstruction',Prompt)>0),
      'generation brief includes submitted prompt source dialogue and resolution'); finally Context.Free; end;
  finally Refs.Free; end;
end;
procedure StartSelected;
begin Button('ScriptSceneAiSelected').Click; Check(W.SceneImageAiBusy,'button starts image processing'); end;
procedure FakeChecks;
begin
  PreviousExe := GetEnvironmentVariable('CODEX_PIPE_EXE'); FixtureMode := GetEnvironmentVariable('RIGM_TEST_IMAGE_MODE');
  Winapi.Windows.SetEnvironmentVariable('RIGM_TEST_IMAGE_PATH',PChar(FixtureImage));
  Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(ParamStr(0)));
  try
    var OriginalCues := CueContent; Mode('path');
    var TypedPrompt := Row(W.ScriptDraft.Scenes[0].Id).Prompt.Text+' 水彩画の優しい色。';
    Row(W.ScriptDraft.Scenes[0].Id).Prompt.Text := TypedPrompt;
    Button('ScriptSceneAiAll').Click;
    Check(W.SceneImageAiBusy and not Button('ScriptSceneAiAll').Enabled,'batch disables duplicate starts');
    Check(W.ScriptDraft.Scenes[0].ImagePrompt=TypedPrompt,'generation button commits the user memo before creating requests');
    Check(Row(W.ScriptDraft.Scenes[0].Id).Prompt.ReadOnly,'image input is protected while generating');
    Check((Frame.FindComponent('ScriptSceneAiProgress') as TProgressBar).Visible and Button('ScriptSceneAiCancel').Visible,'progress and stop controls are visible');
    WaitDone;
    for var S in W.ScriptDraft.Scenes do begin
      Check(S.Image<>'' ,'protocol fixture is adopted for '+S.Id);
      Check(not S.ImageApproved,'receiving does not approve '+S.Id);
      Check(Row(S.Id).Picture.Picture.Graphic<>nil,'row decodes received image '+S.Id);
      Check(JS(ScriptSceneRequest(W.ScriptDraft,S.Id),'imageProvenance')='external-generated','adoption passes through the standard request pipeline');
    end;
    Check(OriginalCues=CueContent,'image generation preserves all dialogue audio subtitle and expression fields');
    var LogText := TFile.ReadAllText(W.SceneImageAiLogPath,TEncoding.UTF8);
    Check((Pos('previous-scene',LogText)>0) and (Pos('localImage',LogText)>0),'second image request attaches the first as a reference');
    Check(Pos('ScriptThumbnailRefs',LogText)>0,'normal scene sends a rendered character PNG instead of its source model');
    Check(Button('ScriptSceneAiAll').Enabled and not Button('ScriptSceneAiCancel').Visible,'completion restores image controls');
    var Id := W.ScriptDraft.Scenes[0].Id;
    Mode('base64'); Select(Id); StartSelected; WaitDone;
    Check(Pos('画像を取得',W.SceneImageAiMessage)>0,'base64-only image result is accepted');
    LogText := TFile.ReadAllText(W.SceneImageAiLogPath,TEncoding.UTF8);
    Check(Pos('image data omitted',LogText)>0,'base64 data is omitted from protocol logs');
    var BeforeImage := W.ScriptDraft.Scene(Id).Image;
    for var Failure in ['no-image','failure'] do begin
      Mode(Failure); StartSelected; WaitDone;
      Check((Pos('停止',W.SceneImageAiMessage)>0) and (W.ScriptDraft.Scene(Id).Image=BeforeImage),Failure+' cannot replace an image');
    end;
    Mode('path'); StartSelected; Pump(100);
    W.ScriptDraft.Scene(Id).ImagePrompt := W.ScriptDraft.Scene(Id).ImagePrompt+' 人間が処理中に変更';
    WaitDone; Check((W.ScriptDraft.Scene(Id).Image=BeforeImage) and (Pos('停止',W.SceneImageAiMessage)>0),'stale image result preserves changes and original image');
    Mode('path'); StartSelected; Pump(100); W.RequestScriptSceneImage(Id);
    var NewRequestId := JS(ScriptSceneRequest(W.ScriptDraft,Id),'requestId');
    WaitDone;
    Check((W.ScriptDraft.Scene(Id).Image=BeforeImage) and (JS(ScriptSceneRequest(W.ScriptDraft,Id),'requestId')=NewRequestId) and
      (JS(ScriptSceneRequest(W.ScriptDraft,Id),'state')='pending'),'obsolete job does not overwrite or cancel a newer external request');
    Mode('delay'); StartSelected; Pump(100); Button('ScriptSceneAiCancel').Click; WaitDone;
    Check((W.ScriptDraft.Scene(Id).Image=BeforeImage) and (Pos('中止',W.SceneImageAiMessage)>0),'cancellation keeps adopted images');
    Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(TPath.Combine(Root,'missing-codex.exe')));
    StartSelected; WaitDone; Check(Button('ScriptSceneAiSelected').Enabled and (W.ScriptDraft.Scene(Id).Image=BeforeImage),'missing executable restores retry without replacing an image');
    Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(ParamStr(0))); Mode('path');
    for var S in W.ScriptDraft.Scenes do W.SetScriptSceneApproved(S.Id,True);
    Check(ScriptThumbnailSourcesReady(W.ScriptDraft),'human confirmation unlocks thumbnail generation');
    Select(RigmThumbnailId); StartSelected; WaitDone;
    Check((W.ScriptDraft.Thumbnail.Image<>'') and not W.ScriptDraft.Thumbnail.ImageApproved,'thumbnail is received and remains unapproved');
    LogText := TFile.ReadAllText(W.SceneImageAiLogPath,TEncoding.UTF8);
    Check((Pos('logoText',LogText)>0) and (Pos('localImage',LogText)>0),'thumbnail sends logo instructions and existing scene image references');
    Check(Pos('ScriptThumbnailRefs',LogText)>0,'thumbnail renders and attaches selected character references');
    W.SaveScriptDraft; var Saved := LoadMovie(W.ScriptDraft.FileName);
    try
      Check((Saved.Scenes[0].Image<>'') and Saved.Scenes[0].ImageApproved and (Saved.Thumbnail.Image<>'') and not Saved.Thumbnail.ImageApproved,
        'images and human approval state survive saving and reloading');
    finally Saved.Free; end;
    Check(OriginalCues=CueContent,'all transport paths keep dialogue and audio unchanged');
  finally
    Winapi.Windows.SetEnvironmentVariable('CODEX_PIPE_EXE',PChar(PreviousExe));
    Winapi.Windows.SetEnvironmentVariable('RIGM_TEST_IMAGE_MODE',PChar(FixtureMode));
    Winapi.Windows.SetEnvironmentVariable('RIGM_TEST_IMAGE_PATH',nil);
  end;
end;
procedure LiveChecks;
begin
  for var S in W.ScriptDraft.Scenes do begin W.SetScriptSceneApproved(S.Id,False); S.Image := ''; end;
  W.ScriptDraft.Thumbnail.Image := ''; var OriginalCues := CueContent;
  W.ScriptDraft.Scenes[0].ImagePrompt := '青い空と海辺の小さな図書館。絵本風のイラスト。文字は入れない。';
  Frame.RefreshState; Button('ScriptSceneAiAll').Click; WaitDone(1250000);
  Check(Pos('2枚の画像を取得',W.SceneImageAiMessage)>0,'actual Codex generates and delivers both images without another click: '+W.SceneImageAiMessage);
  for var S in W.ScriptDraft.Scenes do begin
    var Path := ResolveMoviePath(W.ScriptDraft.FileName,S.Image);
    Check((S.Image<>'') and FileExists(Path) and (TFile.GetSize(Path)>10000),'actual generated image exists '+S.Id);
    Check((Row(S.Id).Picture.Picture.Graphic<>nil) and not S.ImageApproved,'actual generated image is decoded in its row and awaits confirmation');
    Check(CheckedMovieImageHash(Path)<>'','actual image passes production validation');
  end;
  Check(OriginalCues=CueContent,'actual generation keeps all dialogue and audio unchanged');
  TFile.WriteAllText(TPath.Combine(Root,'live-log-path.txt'),W.SceneImageAiLogPath,TEncoding.UTF8);
  W.SaveScriptDraft; var Saved := LoadMovie(W.ScriptDraft.FileName);
  try Check((Saved.Scenes[0].Image<>'') and (Saved.Scenes[1].Image<>''),'actual generated images survive saving and reloading'); finally Saved.Free; end;
end;
begin
  if ParamStr(1)='app-server' then begin ProtocolFixture; Exit; end;
  Application.Initialize; Root := ParamStr(1); ForceDirectories(Root); Checks := TJSONArray.Create;
  var Report := TJSONObject.Create.AddPair('checks',Checks);
  try
    try Prepare; ModelChecks; FakeChecks; if LiveRequested then LiveChecks;
      AddB(Report,'live',LiveRequested); AddB(Report,'success',True);
    except on E: Exception do begin Report.AddPair('error',E.ClassName+': '+E.Message); ExitCode := 1; Writeln('FAIL ',E.Message); end; end;
    TFile.WriteAllText(TPath.Combine(Root,'result.json'),Report.ToJSON,TEncoding.UTF8);
  finally
    Application.OnException := nil; if W<>nil then W.OnScriptChanged := nil;
    Host.Free; W.Free; Observer.Free; Report.Free;
  end;
end.
