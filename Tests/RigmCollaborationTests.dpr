program RigmCollaborationTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  System.Generics.Collections, Winapi.Windows, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage, RigmEditorForm, RigmMovieForm,
  RigmMovieModel, RigmMovieSession, RigmMovieWorkflow, RigmJson, RigmPipeTestClient;
var Host: TRigmEditorForm; Studio: TRigmMovieForm; Root,PipeName: string; Checks: TJSONArray;
function CaptureStack(FramesToSkip,FramesToCapture: DWORD; BackTrace: Pointer; Hash: Pointer): Word; stdcall;
  external 'kernel32.dll' name 'RtlCaptureStackBackTrace';
function InstallTrace(First: Cardinal; Handler: Pointer): Pointer; stdcall;
  external 'kernel32.dll' name 'AddVectoredExceptionHandler';
function FaultTrace(Info: PExceptionPointers): Longint; stdcall;
var Addresses: array[0..31] of Pointer;
begin
  Result := 0;
  if Info.ExceptionRecord.ExceptionCode<>$C0000005 then Exit;
  var Count := CaptureStack(0,Length(Addresses),@Addresses,nil);
  for var I := 0 to Count-1 do Writeln('AVTRACE ',IntToHex(NativeUInt(Addresses[I])-NativeUInt(GetModuleHandle(nil)),16));
end;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Find(Parent: TWinControl; const Name: string): TControl;
begin Result := nil; for var I := 0 to Parent.ControlCount-1 do begin var C := Parent.Controls[I]; if C.Name=Name then Exit(C); if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end; end; end;
procedure Pump(Ms: Cardinal=180);
begin var Deadline := GetTickCount64+Ms; repeat Application.ProcessMessages; Host.Editor.PollMovie; Sleep(5); until GetTickCount64>=Deadline; end;
function Call(const Name: string; Args: TJSONObject=nil): TJSONObject;
begin
  if Args=nil then Args := TJSONObject.Create;
  Args.AddPair('projectId',Host.Editor.Movie.Project.Id); AddN(Args,'revision',Host.Editor.Movie.Project.Revision);
  var Reply := PipeCall(PipeName,'movie-'+Name,Args);
  try if not JB(Reply,'ok') then raise Exception.Create(Reply.ToJSON); Result := JO(Reply,'data').Clone as TJSONObject; finally Reply.Free; end;
end;
procedure Run(const Name: string; const Json: string='{}');
begin var O := Call(Name,ParseObject(Json)); O.Free; end;
function State: TJSONObject; begin Result := Call('workflow-status'); end;
procedure Stage(const Name: string);
begin var O := State; try Check(JS(O,'currentStage')=Name,'explicit current stage '+Name); Check(not JB(O,'automaticAdvance') and not JB(O,'requiresHumanConfirmation'),'stage is explicit without confirmation flag '+Name); finally O.Free; end; end;
procedure Job;
begin
  var Deadline := GetTickCount64+20000;
  repeat Pump(20); var O := Call('job-status'); try if JB(O,'done') then begin Check(JS(O,'state')='succeeded','isolated stage job succeeds: '+JS(O,'state')+' '+JS(O,'error')); Exit; end; finally O.Free; end; until GetTickCount64>=Deadline;
  raise Exception.Create('Job timeout');
end;
procedure Diagnose;
begin
  Run('diagnostics-refresh'); var Deadline := GetTickCount64+8000;
  repeat Pump(20); var O := Call('preparation'); try if JB(O,'diagnosticsCurrent') and not JB(O,'diagnosticsBusy') then begin Pump(250); Exit; end; finally O.Free; end; until GetTickCount64>=Deadline;
  raise Exception.Create('Diagnosis timeout');
end;
procedure Click(const Name: string); begin TButton(Find(Studio,Name)).Click; Pump; end;
procedure CueEdit(const Field,Value: string);
begin TMemo(Find(Studio,Field)).Text := Value; Click('MovieApplyCue'); end;
procedure Tests;
var O,A: TJSONObject; P: TRigmMovieProject; SourceHash,FirstHash,FirstVideo,SecondVideo: string;
begin
  P := TRigmMovieProject.Create;
  try Check((P.Width=1920) and (P.Height=1080) and (P.Fps=30),'new project defaults to existing FullHD preset including unspecified fps'); finally P.Free; end;
  O := ParseObject('{"width":1280,"height":720,"fps":24}'); P := TRigmMovieProject.FromJson(O); O.Free;
  try Check((P.Width=1280) and (P.Height=720) and (P.Fps=24),'existing authored dimensions and fps are preserved'); finally P.Free; end;
  Host := TRigmEditorForm.Create(nil);
  try
    Host.OpenSample; Host.Editor.Save(TPath.Combine(Root,'protected-host.rigm')); SourceHash := THashSHA2.GetHashStringFromFile(Host.Editor.FileName);
    var PipeDirectory := ''; for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--pipe-dir=') then PipeDirectory := ParamStr(I).Substring(11);
    O := ParseObject(TFile.ReadAllText(TDirectory.GetFiles(PipeDirectory,'*.control.json')[0],TEncoding.UTF8)); try PipeName := JS(O,'commandPipe'); finally O.Free; end;
    Studio := TRigmMovieForm.CreateForSession(nil,Host.Editor.Movie); Studio.Show; Pump;
    O := Call('schema'); try Check(JO(O,'commands').Count=64,'common pipe exposes 64 commands with staged and optional batch APIs'); finally O.Free; end;
    Stage('script'); Run('workflow-next'); Stage('script');
    Run('workflow-run','{"text":"narrator:A fictional shop opens."}'); Pump;
    Check(TMemo(Find(Studio,'MovieCueText')).Text='A fictional shop opens.','Codex script arrives in the shared GUI');
    CueEdit('MovieCueText','A fictional shop opens quietly.');
    Check(Host.Editor.Movie.Project.Cues[0].Text='A fictional shop opens quietly.','human GUI script adjustment returns to pipe model');
    Click('MovieNextStep'); Stage('setup');
    Run('update-project','{"character":"@sample","engineUrl":"http://127.0.0.1:51237"}'); Pump;
    Check(Find(Studio,'MovieVoiceStyle')<>nil,'voice selector exists before setup job');
    Run('workflow-run'); Check(True,'setup job request returned'); Diagnose; Check(True,'setup diagnosis returned');
    var Style := TComboBox(Find(Studio,'MovieVoiceStyle')); var StyleDeadline := GetTickCount64+5000; var FixtureStyle := -1;
    repeat Pump(40); for var I := 0 to Style.Items.Count-1 do if NativeInt(Style.Items.Objects[I])=101 then FixtureStyle := I; until (FixtureStyle>=0) or (GetTickCount64>=StyleDeadline);
    Check((Style<>nil) and (FixtureStyle>=0),'diagnosis populated current fixture GUI voice choices'); Style.ItemIndex := FixtureStyle; if Assigned(Style.OnChange) then Style.OnChange(Style); Click('MovieApplyVoice');
    Check(Host.Editor.Movie.Project.Speakers[0].StyleId=101,'GUI assigns catalog voice to shared setup stage');
    FirstVideo := TPath.Combine(Root,'first.avi'); SecondVideo := TPath.Combine(Root,'second.avi');
    TEdit(Find(Studio,'MovieDimensions')).Text := '320 x 180 x 10'; TEdit(Find(Studio,'MovieOutputTarget')).Text := FirstVideo; Click('MovieApplySettings');
    Check((Host.Editor.Movie.Project.Width=320) and (Host.Editor.Movie.Project.Height=180) and (Host.Editor.Movie.Project.Fps=10),'explicit user output override is retained');
    Diagnose; Run('workflow-next'); Stage('audio');
    A := TJSONObject.Create; A.AddPair('directory',TPath.Combine(Root,'Audio')); O := Call('workflow-run',A); O.Free; Job; Stage('audio');
    O := State; try Check(JB(O,'canNext') and JB(JO(O,'results'),'audioCurrent'),'audio generation completes without advancing'); finally O.Free; end;
    TEdit(Find(Studio,'MovieVoiceSpeed')).Text := '1.2'; Click('MovieApplyVoice');
    O := State; try Check(not JB(O,'canNext') and not JB(JO(O,'results'),'audioCurrent'),'GUI voice revision invalidates audio and blocks next'); finally O.Free; end;
    A := TJSONObject.Create; A.AddPair('directory',TPath.Combine(Root,'Audio')); O := Call('workflow-run',A); O.Free; Job;
    Click('MovieNextStep'); Stage('preview');
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'preview-first.png')); O := Call('workflow-run',A); O.Free; Job; Stage('preview');
    Check(not TRigmMoviePreview(Find(Studio,'MoviePreviewImage')).Frame.Empty,'Codex stage preview appears on GUI');
    CueEdit('MovieCueSubtitle','Human edited subtitle');
    O := State; try Check(JB(JO(O,'results'),'audioCurrent') and not JB(JO(O,'results'),'previewCurrent'),'subtitle edit preserves audio and marks downstream preview stale'); finally O.Free; end;
    Run('workflow-next'); Stage('preview');
    Click('MovieRunStep'); Job; Click('MovieNextStep'); Stage('export');
    Run('workflow-run'); Job; Stage('export');
    Check(FileExists(FirstVideo),'Codex export writes actual video before explicit next'); FirstHash := THashSHA2.GetHashStringFromFile(FirstVideo);
    CueEdit('MovieCueSubtitle','A final jointly adjusted subtitle');
    O := State; try Check(not JB(JO(O,'results'),'videoCurrent') and not JB(O,'canNext'),'GUI export-stage adjustment invalidates video and blocks completion'); finally O.Free; end;
    Click('MovieBackStep'); Stage('preview'); Click('MovieRunStep'); Job;
    Run('workflow-next'); Stage('export'); Pump; // Refresh displayed revision before editing settings.
    TEdit(Find(Studio,'MovieOutputTarget')).Text := SecondVideo; Click('MovieApplySettings');
    Run('workflow-run'); Job;
    Check(FileExists(SecondVideo) and (THashSHA2.GetHashStringFromFile(FirstVideo)=FirstHash),'regeneration creates new video and retains prior result');
    Click('MovieNextStep'); Stage('complete');
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'collaborative.rigmovie')); O := Call('save',A); O.Free;
    var Before := MovieRenderKey(Host.Editor.Movie.Project);
    A := TJSONObject.Create; A.AddPair('path',TPath.Combine(Root,'collaborative.rigmovie')); O := Call('open',A); O.Free; Pump; Diagnose;
    O := State; try Check((JS(O,'currentStage')='complete') and JB(O,'ready') and JB(JO(O,'results'),'previewCurrent') and JB(JO(O,'results'),'videoCurrent'),'save and reopen restores workflow and content-valid results'); finally O.Free; end;
    Check(MovieRenderKey(Host.Editor.Movie.Project)=Before,'portable asset paths preserve render identity across save reopen');
    Run('workflow-back','{"stage":"script"}'); Stage('script');
    Run('add-cue','{"cue":{"id":"extra-row","text":"","subtitle":"Alternate row"}}'); Pump;
    CueEdit('MovieCueText','Unsaved human draft');
    var Dialogue := TMemo(Find(Studio,'MovieCueText')); Dialogue.Text := 'Pending human draft';
    var List := TListView(Find(Studio,'MovieCueList')); List.Items[1].Selected := True; Pump;
    Check((Dialogue.Text='Pending human draft') and (List.Selected=List.Items[0]),'cue switching preserves pending input and stable selection');
    var CurrentRevision := Host.Editor.Movie.Project.Revision;
    Run('update-project','{"title":"Concurrent Codex title"}'); Pump(400);
    Check(Dialogue.Text='Pending human draft','GUI pending input survives concurrent Codex edit');
    Click('MovieApplyCue');
    Check((Host.Editor.Movie.Project.Revision=CurrentRevision+1) and (Host.Editor.Movie.Project.Cues[0].Text='Unsaved human draft'),'stale GUI draft cannot overwrite newer pipe revision');
    Check(TButton(Find(Studio,'MovieReloadDraft')).Visible,'conflict offers explicit latest-data reload without confirmation flag');
    Click('MovieReloadDraft'); Check(Dialogue.Text='Unsaved human draft','explicit reload returns shared current data');
    A := TJSONObject.Create; A.AddPair('projectId',Host.Editor.Movie.Project.Id); AddN(A,'revision',1); A.AddPair('title','stale'); O := PipeCall(PipeName,'movie-update-project',A);
    try Check(not JB(O,'ok'),'common pipe rejects stale author revision'); finally O.Free; end;
    O := State; try Check(JA(O,'regenerate').ToJSON='["audio","preview","export"]','script change reports exact downstream regeneration set'); finally O.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Host.Editor.FileName)=SourceHash,'all staged actions preserve hosting source RIGM');
    // A separate owned session models a host update occurring after a worker snapshot.
    var S := TRigmMovieSession.Create;
    try
      var Q := TRigmMovieProject.FromText('narrator:A fresh isolated worker test.'); Q.Width := 320; Q.Height := 180; Q.Fps := 10; Q.EngineUrl := 'http://127.0.0.1:51237'; Q.CharacterFile := '@sample'; Q.Speakers[0].StyleId := 101; S.SetProject(Q);
      A := TJSONObject.Create; A.AddPair('directory',TPath.Combine(Root,'StaleAudio')); O := S.Execute('audio-generate',A); O.Free; A.Free;
      S.Project.Cues[0].Text := 'Newer authored worker text'; S.Project.Changed;
      var Deadline := GetTickCount64+10000; while S.Busy and (GetTickCount64<Deadline) do Sleep(10); S.Poll;
      A := TJSONObject.Create; O := S.Execute('job-status',A); A.Free;
      try Check(JB(O,'staleResult') and not S.Project.AudioReady(S.Project.Cues[0]),'stale audio worker is rejected and cannot replace newer authorship'); finally O.Free; end;
      A := TJSONObject.Create; O := S.Execute('preview',A); O.Free; A.Free; S.Project.Cues[0].Subtitle := 'newer subtitle'; S.Project.Changed;
      Deadline := GetTickCount64+10000; while S.Busy and (GetTickCount64<Deadline) do Sleep(10); S.Poll;
      A := TJSONObject.Create; O := S.Execute('job-status',A); A.Free;
      try Check(JB(O,'staleResult') and (S.TakeFrame=nil),'stale preview worker is rejected before GUI frame replacement'); finally O.Free; end;
    finally S.Free; end;
    var Bitmap := TBitmap.Create; var Image := TPngImage.Create;
    try Bitmap.SetSize(Studio.ClientWidth,Studio.ClientHeight); Studio.PaintTo(Bitmap.Canvas,0,0); Image.Assign(Bitmap); Image.SaveToFile(TPath.Combine(Root,'cooperative-studio.png')); finally Image.Free; Bitmap.Free; end;
    Check(string(TLabel(Find(Studio,'MovieWorkflowGuide')).Caption).Contains('台本'),'GUI current-stage guide agrees with pipe stage');
  finally Studio.Free; Studio := nil; Host.Free; end;
end;
begin
  Application.Initialize; InstallTrace(1,@FaultTrace); Checks := TJSONArray.Create;
  for var I := 1 to ParamCount do if ParamStr(I).StartsWith('--collaboration-dir=') then Root := ParamStr(I).Substring(20);
  ForceDirectories(Root);
  var Report := TJSONObject.Create;
  try
    try Tests; AddB(Report,'success',True); except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); AddB(Report,'success',False); Report.AddPair('error',E.Message); ExitCode := 1; end; end;
    AddN(Report,'passed',Checks.Count); Report.AddPair('checks',Checks.Clone as TJSONArray); Report.AddPair('directory',Root);
    Report.AddPair('audioSource','explicit HTTP TEST TONE fixture, no actual speech'); AddB(Report,'realSpeechVerified',False);
    TFile.WriteAllText(TPath.Combine(ExtractFilePath(ParamStr(0)),'collaboration-results.json'),Report.ToJSON,TEncoding.UTF8);
  finally Report.Free; Checks.Free; end;
end.
