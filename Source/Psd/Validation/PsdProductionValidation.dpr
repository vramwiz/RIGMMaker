program PsdProductionValidation;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, System.Math, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics, Vcl.Imaging.pngimage,
  PsdJson, PsdCharacter, PsdWorkspace, PsdPackage, PsdProduction, PsdSession,
  PsdAnimation, PsdStudioForm, PsdMotionReferenceForm, PsdPreviewControl, Winapi.Windows, Winapi.Messages, RigmCharacterCatalog,
  RigmMovieModel, RigmMovieComposition, RigmMovieCompositionCommands, RigmMovieSession, RigmMovieCreator;
var Passed: Integer;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create('FAIL: '+Name); Inc(Passed); Writeln('PASS: '+Name); end;
procedure Reject(Action: TProc; const Name: string);
begin var Rejected := False; try Action(); except on E: Exception do Rejected := True; end; Check(Rejected,Name); end;
function Args(Session: TPsdSession): TJSONObject;
begin
  var Status := Session.Status;
  try Result := TJSONObject.Create; Result.AddPair('sessionId',S(Status,'sessionId')); Result.AddPair('revision',S(Status,'revision'));
  finally Status.Free; end;
end;
procedure Run(Session: TPsdSession; const Name: string; A: TJSONObject);
begin try var Result := Session.Command(Name,A); Result.Free; finally A.Free; end; end;
function Reference(C: TPsdCharacter): TJSONObject;
  function Point(X,Y: Double): TJSONObject;
  begin Result := TJSONObject.Create; Result.AddPair('x',TJSONNumber.Create(X*C.Document.Width)); Result.AddPair('y',TJSONNumber.Create(Y*C.Document.Height)); end;
begin
  Result := ObjectText('{"schemaVersion":1,"source":"ai"}'); var F := TJSONObject.Create; Result.AddPair('faceBounds',F);
  F.AddPair('left',TJSONNumber.Create(C.Document.Width*0.35)); F.AddPair('top',TJSONNumber.Create(C.Document.Height*0.08));
  F.AddPair('right',TJSONNumber.Create(C.Document.Width*0.65)); F.AddPair('bottom',TJSONNumber.Create(C.Document.Height*0.30));
  Result.AddPair('neck',Point(0.5,0.32)); Result.AddPair('screenLeftShoulder',Point(0.3,0.37)); Result.AddPair('screenRightShoulder',Point(0.7,0.37));
  Result.AddPair('upperBodyBottomY',TJSONNumber.Create(C.Document.Height*0.65));
end;
procedure Tests;
begin
  var Original := 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar';
  var OriginalHash := THashSHA2.GetHashStringFromFile(Original);
  var Root := TPath.Combine(ExtractFilePath(ParamStr(0)),'ProductionData\'+NewId); var W := TPsdWorkspace.Create(Root);
  var Session: TPsdSession := nil;
  try
    W.Initialize; TFile.Copy(Original,W.Resolve('Characters\fixture.psdchar',False),False);
    Session := TPsdSession.Create(Root,False); var A := Args(Session); A.AddPair('path','Characters\fixture.psdchar'); Run(Session,'open',A);
    var Reason: string;
    Check(not PsdReadyForScript(Session.Character,Reason),'existing registration loads as incomplete');
    Check(not CharacterReadyForNewScript(Session.SavedPath,Reason),'incomplete registration rejected for new script');
    var Editor := TPsdStudioForm.CreateForCharacter(nil,Root,Session.SavedPath);
    try Check(Editor.Session.Character.Id=Session.Character.Id,'incomplete registration opens character editor'); finally Editor.Free; end;
    var Bad := Reference(Session.Character); Put(Obj(Bad,'neck'),'x',TJSONNumber.Create(-1));
    var Before := THashSHA2.GetHashStringFromFile(Session.SavedPath); A := Args(Session); A.AddPair('reference',Bad);
    Reject(procedure begin Run(Session,'set-motion-reference',A); end,'invalid motion reference refused by AI pipe command');
    Check(THashSHA2.GetHashStringFromFile(Session.SavedPath)=Before,'invalid reference preserves saved package');
    A := Args(Session); A.AddPair('reference',Reference(Session.Character)); Run(Session,'set-motion-reference',A);
    Check(not Session.Dirty,'draft motion reference saves automatically');
    ValidateMotionReference(Session.Character,Obj(Session.Character.Settings,'motionReference'));
    var ReferenceEditor := TPsdStudioForm.CreateForCharacter(nil,Root,Session.SavedPath);
    var Pages := TPageControl(ReferenceEditor.FindComponent('PsdCharacterPages'));
    Pages.ActivePageIndex := 2; Pages.OnChange(Pages);
    var Form := TPsdMotionReferencePage(ReferenceEditor.FindComponent('PsdMotionReferenceEditor'));
    try
      ValidateMotionReference(Session.Character,Form.Reference);
      Check(S(Form.Reference,'source')='ai','GUI displays AI-created reference without rewriting it');
      ReferenceEditor.Position := poDesigned; ReferenceEditor.SetBounds(-1400,-1000,1280,840); ReferenceEditor.Show; ReferenceEditor.Update; Application.ProcessMessages;
      var Canvas := TPsdPreviewControl(Form.FindComponent('MotionReferenceCanvas'));
      Canvas.Update; var R := Canvas.ImageRect;
      for var Step := 0 to 5 do begin
        var X,Y: Double;
        case Step of
          0: begin X:=0.35; Y:=0.08; end; 1: begin X:=0.65; Y:=0.30; end;
          2: begin X:=0.5; Y:=0.32; end; 3: begin X:=0.3; Y:=0.37; end;
          4: begin X:=0.7; Y:=0.37; end; else begin X:=0.5; Y:=0.65; end;
        end;
        TComboBox(Form.FindComponent('MotionReferenceStep')).ItemIndex := Step;
        var Position := MakeLParam(R.Left+Round(X*R.Width),R.Top+Round(Y*R.Height));
        Canvas.Perform(WM_LBUTTONDOWN,MK_LBUTTON,Position); Canvas.Perform(WM_LBUTTONUP,0,Position);
      end;
      Canvas.Update; Form.Update; ValidateMotionReference(Session.Character,Form.Reference);
      Check(S(Form.Reference,'source')='manual','native GUI clicks produce valid shared motion reference');
      var Bitmap := Vcl.Graphics.TBitmap.Create; var Png := TPngImage.Create;
      try Bitmap.SetSize(Form.ClientWidth,Form.ClientHeight); Form.PaintTo(Bitmap.Canvas.Handle,0,0);
        Png.Assign(Bitmap); Png.SaveToFile(TPath.Combine(Root,'motion-reference-gui.png'));
      finally Png.Free; Bitmap.Free; end;
      TButton(Form.FindComponent('MotionReferenceSave')).Click;
      Check(not Form.HasDraft and (S(Obj(ReferenceEditor.Session.Character.Settings,'motionReference'),'source')='manual'),'embedded motion step applies a valid reference');
    finally ReferenceEditor.Free; end;
    A := Args(Session); A.AddPair('path',Session.SavedPath); Run(Session,'open',A);
    var Saved := LoadCharacter(W,Session.SavedPath);
    try
      ValidateMotionReference(Saved,Obj(Saved.Settings,'motionReference')); Check(True,'motion reference survives save and restart');
      Check(PsdProductionDigest(Saved)=PsdProductionDigest(Session.Character),'inspection digest stable after PSD package roundtrip');
    finally Saved.Free; end;
    A := Args(Session); A.AddPair('name',Session.Character.Name); A.AddPair('supplementName','検証用衣装'); Run(Session,'set-info',A);
    Check(not Session.Dirty,'draft character information saves automatically');
    Run(Session,'check-production',Args(Session));
    Check(B(Session.Character.Production,'checked') and not B(Session.Character.Production,'ready'),'inspection records incomplete result');
    var Blink,Lip,Motion: Boolean; Blink := False; Lip := False; Motion := False;
    for var V in Arr(Session.Character.Production,'checks') do begin var O := TJSONObject(V);
      if S(O,'id')='blink' then Blink := B(O,'passed'); if S(O,'id')='lipSync' then Lip := B(O,'passed'); if S(O,'id')='motionReference' then Motion := B(O,'passed');
    end;
    Check(Blink and Lip and Motion,'existing blink/phonemes and valid reference pass structural checks');
    Saved := LoadCharacter(W,Session.SavedPath);
    try
      Check((Saved.SupplementName='検証用衣装') and B(Saved.Production,'checked') and not PsdReadyForScript(Saved,Reason),'inspection and metadata survive restart without manual completion flag');
    finally Saved.Free; end;
    var R := TPsdRenderer.Create(Session.Character,W,240);
    try
      var State := TPsdFrameState.Default; State.AutoBlink := False; State.Seconds := 1;
      var Breathing := R.Frame(State,320,180); State.Motion := 'none'; var Still := R.Frame(State,320,180);
      Check(Length(Breathing)=320*180*4,'reference-based breathing renders');
      var Fit := Min(320*0.9/R.Document.Width,180*0.9/R.Document.Height);
      var BottomY := 180*0.95-R.Document.Height*Fit+N(Obj(Session.Character.Settings,'motionReference'),'upperBodyBottomY')/Session.Character.Document.Height*R.Document.Height*Fit;
      var Start := Min(Length(Still),Max(0,Ceil(BottomY)+2)*320*4);
      Check(CompareMem(@Still[Start],@Breathing[Start],Length(Still)-Start),'breathing leaves pixels below upper-body reference unchanged');
      State.Motion := 'sway'; Check(Length(R.Frame(State,320,180))=320*180*4,'reference-based sway renders');
    finally R.Free; end;
    var Movie := TRigmMovieProject.Create;
    try
      var Actor := TRigmMovieCharacter.Create; Actor.FileName := Session.SavedPath; Actor.RenderFormat := 'psd';
      A := TJSONObject.Create; A.AddPair('character',Actor.Json); Actor.Free;
      try Reject(procedure begin ApplyCompositionCommand(Movie,'add-character',A); end,'new character command enforces incomplete restriction');
      finally A.Free; end;
      Check(Movie.Characters.Count=0,'rejected addition leaves movie unchanged');
      // 保存済み作品の読み込みを再現する。読み込み時に新規追加検査を実行しない。
      Actor := TRigmMovieCharacter.Create; Actor.FileName := Session.SavedPath; Actor.RenderFormat := 'psd'; Movie.Characters.Add(Actor);
      var Json := Movie.Json;
      try var Reopened := TRigmMovieProject.FromJson(Json);
        try Check(Reopened.Characters.Count=1,'saved movie retains previously used incomplete character'); finally Reopened.Free; end;
      finally Json.Free; end;
    finally Movie.Free; end;
    var MovieSession := TRigmMovieSession.Create; var Host := TForm.CreateNew(nil);
    try
      var Creation := TRigmMovieCreator.CreateForWorkspace(Host,TPath.Combine(Root,'Library'));
      Creation.Bind(MovieSession,nil);
      var List := TListView(Creation.FindComponent('CreationCharacters')); var Item: TListItem := nil;
      for var Index := 0 to List.Items.Count-1 do if TCreationEntry(List.Items[Index].Data).FileName=Session.SavedPath then Item := List.Items[Index];
      Check((Item<>nil) and Item.Caption.Contains('未完成'),'script GUI visibly identifies incomplete character');
      Item.Checked := True;
      Check(not Item.Checked and (MovieSession.Project.Characters.Count=0),'script GUI refuses checking an incomplete character');
    finally Host.Free; MovieSession.Free; end;
    Check(THashSHA2.GetHashStringFromFile(Original)=OriginalHash,'user registration remains byte-for-byte unchanged');
    Writeln('PASS TOTAL: '+Passed.ToString); TFile.WriteAllText(TPath.Combine(Root,'result.txt'),'PASS TOTAL: '+Passed.ToString,TEncoding.UTF8);
    Writeln('ARTIFACT ROOT: '+Root);
  finally Session.Free; W.Free; end;
end;
begin
  try Application.Initialize; Tests;
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
