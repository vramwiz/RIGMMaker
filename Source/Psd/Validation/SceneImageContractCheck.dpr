program SceneImageContractCheck;
// Isolated native verification. Optional generated-image folder and owned fixture root.
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.JSON, System.Hash, System.IOUtils,
  Vcl.Imaging.pngimage, RigmMovieModel, RigmMovieComposition, RigmJson, PsdJson,
  RigmScriptCastingModel, RigmScriptReviewModel, RigmScriptScenesModel,
  RigmScriptSceneAssignmentModel, RigmMovieImageTransfer;
var P: TRigmMovieProject; Checks: Integer; Directory,ImagePath: string;
procedure Check(Value: Boolean; const MessageText: string);
begin if not Value then raise Exception.Create(MessageText); Inc(Checks); end;
procedure Reject(Action: TProc; const MessageText: string);
begin var Rejected := False; try Action(); except on E: Exception do Rejected := True; end; Check(Rejected,MessageText); end;
begin
  var FixtureRoot := ParamStr(2); if FixtureRoot='' then FixtureRoot := TPath.GetTempPath;
  Directory := TPath.Combine(FixtureRoot,'RIGM-scene-contract-'+PsdJson.NewId);
  ForceDirectories(Directory); P := TRigmMovieProject.Create;
  try
    ImagePath := TPath.Combine(Directory,'fixture.png'); var Image := TPngImage.CreateBlank(COLOR_RGB,8,32,16);
    try Image.SaveToFile(ImagePath); finally Image.Free; end;
    P.FileName := TPath.Combine(Directory,'fixture.rigmovie');
    P.ScriptWizard := PsdJson.ObjectText('{"scriptText":{"sections":[{"id":"body","text":"1\r\n2\r\n3\r\n4"}]},"casting":{"roles":[],"rows":[]},"scenes":{"format":"RIGMMaker.ScriptScenes","schemaVersion":1,"requests":[]}}');
    var S := TRigmMovieScene.Create; P.Scenes.Add(S); S.ImagePrompt := 'fixture image'; S.Description := ''; S.Image := ImagePath;
    for var I := 0 to 3 do begin
      var C := TRigmMovieCue.Create; P.Cues.Add(C); C.Scene := S.Id; C.Text := (I+1).ToString; C.Subtitle := 'subtitle '+C.Text; C.VoiceReading := 'reading '+C.Text;
      var Row := TJSONObject.Create; JA(JO(P.ScriptWizard,'casting'),'rows').AddElement(Row);
      Row.AddPair('cueId',C.Id); Row.AddPair('section','body'); AddN(Row,'offset',I*3); AddN(Row,'length',1);
    end;
    var Cast := JO(P.ScriptWizard,'casting'); PsdJson.Put(Cast,'sourceFingerprint',ScriptFingerprint(P)); PsdJson.Put(Cast,'fingerprint',CastingFingerprint(P));
    PsdJson.Put(JO(P.ScriptWizard,'scenes'),'castingFingerprint',CastingFingerprint(P)); PsdJson.Put(JO(P.ScriptWizard,'scenes'),'selectedScene',S.Id);
    var SourceHash := THashSHA2.GetHashStringFromFile(ImagePath);
    var Copied := CopyCheckedMovieImage(ImagePath,TPath.Combine(Directory,'Images'),SourceHash);
    Check((Copied<>ImagePath) and (THashSHA2.GetHashStringFromFile(Copied)=SourceHash),'managed content-addressed copy');
    Check(CopyCheckedMovieImage(ImagePath,TPath.Combine(Directory,'Images'),SourceHash)=Copied,'idempotent same image');
    Reject(procedure begin CopyCheckedMovieImage(ImagePath,TPath.Combine(Directory,'Images'),StringOfChar('0',64)); end,'hash mismatch');
    Reject(procedure begin CopyCheckedMovieImage(Directory+'\..\fixture.png',TPath.Combine(Directory,'Images')); end,'traversal');
    var Bad := TPath.Combine(Directory,'bad.png'); TFile.WriteAllText(Bad,'broken PNG');
    Reject(procedure begin CopyCheckedMovieImage(Bad,TPath.Combine(Directory,'Images')); end,'broken decode');
    Check(not ScriptScenesReady(P),'image presence never approves');
    var R := RequestScriptSceneImage(P,S.Id); var OldRequest := JS(R,'requestId');
    SetScriptSceneApproved(P,S.Id,True); Check(ScriptScenesReady(P,True),'explicit approval with optional empty caption');
    Reject(procedure begin ApplyScriptSceneImage(P,S.Id,Copied,OldRequest); end,'approved while request in flight');
    Reject(procedure begin EditScriptScene(P,S.Id,'caption','prompt','both'); end,'approved caption/prompt protection');
    Reject(procedure begin RequestScriptSceneImage(P,S.Id); end,'no request for approved scene');
    SetScriptSceneApproved(P,S.Id,False);
    Reject(procedure begin ApplyScriptSceneImage(P,S.Id,Copied,OldRequest); end,'unlock does not replay old request');
    EditScriptSceneFeedback(P,S.Id,'correction only'); Check(S.Description='' ,'feedback separate from video text');
    R := RequestScriptSceneImage(P,S.Id); var NewRequest := JS(R,'requestId');
    var Other := TRigmMovieScene.Create; Other.ImagePrompt := 'other'; Other.Image := ImagePath; P.Scenes.Add(Other);
    Reject(procedure begin ApplyScriptSceneImage(P,Other.Id,Copied,NewRequest); end,'scene-ID mismatch');
    P.Scenes.Exchange(0,1); Check(ScriptSceneNumber(P,S.Id)=2,'display number changes'); RequireSceneImageRequest(P,S.Id,NewRequest);
    P.Scenes.Exchange(0,1); P.Scenes.Remove(Other);
    ApplyScriptSceneImage(P,S.Id,Copied,NewRequest); Check(S.Image=Copied,'current request applies to fixed ID');
    Reject(procedure begin ApplyScriptSceneImage(P,S.Id,ImagePath,NewRequest); end,'adopted request cannot replay');
    SetScriptSceneApproved(P,S.Id,True); var Approval := S.ImageApprovalKey;
    PsdJson.Put(S.Animation,'enter','fade'); AddN(S.Animation,'enterSeconds',0.2); S.Padding := 0.3;
    Check(ScriptSceneReady(P,S,True),'downstream animation does not invalidate image approval');
    var C := P.Clone; try Check(C.Scenes[0].ImageApproved and (C.Scenes[0].ImageApprovalKey=Approval),'approval survives serialization'); finally C.Free; end;
    var BeforeCue := P.Cues[0].Json; var BeforeText := BeforeCue.ToJSON; BeforeCue.Free;
    SetScriptSceneStart(P,P.Cues[2].Id,True); Check(not P.Scenes[0].ImageApproved,'membership change reopens review');
    Check(P.Scenes[0].Image=Copied,'partition preserves previous image');
    var AfterCue := P.Cues[0].Json; try Check(AfterCue.ToJSON=BeforeText,'cue text/voice unchanged'); finally AfterCue.Free; end;
    Check(THashSHA2.GetHashStringFromFile(ImagePath)=SourceHash,'source image preserved');
    if ParamStr(1)<>'' then begin
      for var I := 1 to 4 do begin
        var Source := TPath.Combine(ParamStr(1),Format('scene-%.3d.png',[I]));
        var GeneratedHash := THashSHA2.GetHashStringFromFile(Source);
        var Managed := CopyCheckedMovieImage(Source,TPath.Combine(Directory,'GeneratedImages'),GeneratedHash);
        Check(CheckedMovieImageHash(Managed,True)=GeneratedHash,'generated PNG including caBX decodes and copies '+I.ToString);
        Check(CopyCheckedMovieImage(Source,TPath.Combine(Directory,'GeneratedImages'),GeneratedHash)=Managed,'generated image copy is idempotent '+I.ToString);
        Check(THashSHA2.GetHashStringFromFile(Source)=GeneratedHash,'generated original preserved '+I.ToString);
      end;
      var Bytes := TFile.ReadAllBytes(TPath.Combine(ParamStr(1),'scene-001.png')); var Offset := 8; var Altered := False;
      while Offset+12<=Length(Bytes) do begin
        var Size := Int64(Bytes[Offset])*16777216+Int64(Bytes[Offset+1])*65536+Int64(Bytes[Offset+2])*256+Bytes[Offset+3];
        if (Bytes[Offset+4]=Ord('c')) and (Bytes[Offset+5]=Ord('a')) and (Bytes[Offset+6]=Ord('B')) and (Bytes[Offset+7]=Ord('X')) and (Size>0) then begin
          Bytes[Offset+8] := Bytes[Offset+8] xor 1; Altered := True; Break;
        end;
        Inc(Offset,Size+12);
      end;
      Check(Altered,'generated fixture contains caBX metadata');
      var Corrupt := TPath.Combine(Directory,'corrupt-cabx.png'); TFile.WriteAllBytes(Corrupt,Bytes);
      Reject(procedure begin CheckedMovieImageHash(Corrupt,True); end,'caBX metadata CRC corruption rejected');
    end;
    Writeln(Checks.ToString+' native model/image assertions passed. Fixture retained at '+Directory);
  except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
  P.Free;
end.
