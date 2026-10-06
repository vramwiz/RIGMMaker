program PsdCompletionValidation;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  PsdJson, PsdCharacter, PsdWorkspace, PsdPackage, PsdProduction, PsdSession;
var Passed: Integer;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create('FAIL: '+Name); Inc(Passed); Writeln('PASS: '+Name); end;
function PassedCheck(Report: TJSONObject; const Id: string): Boolean;
begin Result := False; for var V in Arr(Report,'checks') do if S(TJSONObject(V),'id')=Id then Exit(B(TJSONObject(V),'passed')); end;
function Args(Session: TPsdSession): TJSONObject;
begin var Status := Session.Status; try Result := TJSONObject.Create; Result.AddPair('sessionId',S(Status,'sessionId')); Result.AddPair('revision',S(Status,'revision')); finally Status.Free; end; end;
procedure Run(Session: TPsdSession; const Command: string; A: TJSONObject);
begin try var Reply := Session.Command(Command,A); Reply.Free; finally A.Free; end; end;
procedure Tests;
begin
  var Original := 'D:\Users\take6\RIGMMaker\Characters\blonde-android-20261005.psdchar'; var OriginalHash := THashSHA2.GetHashStringFromFile(Original);
  var Root := TPath.Combine('C:\Users\vramw\AppData\Local\Temp','RIGMMaker-CompletionCheck-'+NewId.Replace('{','').Replace('}',''));
  var W := TPsdWorkspace.Create(Root); var C: TPsdCharacter := nil; var Session: TPsdSession := nil;
  try
    W.Initialize; var Path := W.Resolve('Characters\fixture.psdchar',False); TFile.Copy(Original,Path,False); C := LoadCharacter(W,Path);
    for var Name in ['楽しみ','楽しい','楽'] do Obj(C.Settings,'expressions').RemovePair(Name).Free;
    C.Settings.RemovePair('motionReference').Free;
    var Report := CheckPsdProduction(C);
    try Check(not PassedCheck(Report,'emotions'),'copied fixture identifies missing fun emotion'); Check(PassedCheck(Report,'blink') and PassedCheck(Report,'lipSync'),'real normal expression visibly blinks and switches vowel images'); finally Report.Free; end;
    var Fun := TJSONObject(Obj(Obj(C.Settings,'expressions'),'喜び').Clone); Put(Obj(C.Settings,'expressions'),'楽しみ',Fun);
    Report := CheckPsdProduction(C); try Check(not PassedCheck(Report,'emotions'),'renaming identical emotion pixels cannot satisfy completion'); finally Report.Free; end;
    for var V in Arr(Fun,'variants') do begin
      var Choice := TJSONObject(V); var G := C.Group(S(Choice,'groupId')); var Desired := '';
      if S(G,'name')='口' then Desired := '*あ' else if S(G,'name')='感情記号' then Desired := '*ハート' else if S(G,'name')='体' then Desired := '*通常';
      if Desired<>'' then for var Part in Arr(G,'partIds') do if C.Document.FindLayer(Part.Value).Name=Desired then Put(Choice,'partId',Part.Value);
    end;
    Put(Fun,'productionMethod','existing-layer-combination');
    Report := CheckPsdProduction(C); try Check(PassedCheck(Report,'emotions') and not B(Report,'ready'),'existing self-created parts provide five distinct expressions; reference still required'); finally Report.Free; end;
    var Ref := ObjectText('{"schemaVersion":1,"source":"manual","faceBounds":{"left":0,"top":0,"right":1,"bottom":1},"neck":{"x":0,"y":0},"screenLeftShoulder":{"x":0,"y":0},"screenRightShoulder":{"x":1,"y":0},"upperBodyBottomY":1}');
    Put(Obj(Ref,'faceBounds'),'left',TJSONNumber.Create(C.Document.Width*0.35)); Put(Obj(Ref,'faceBounds'),'top',TJSONNumber.Create(C.Document.Height*0.08));
    Put(Obj(Ref,'faceBounds'),'right',TJSONNumber.Create(C.Document.Width*0.65)); Put(Obj(Ref,'faceBounds'),'bottom',TJSONNumber.Create(C.Document.Height*0.30));
    for var Key in ['neck','screenLeftShoulder','screenRightShoulder'] do begin
      var X := 0.5; if Key='screenLeftShoulder' then X := 0.3 else if Key='screenRightShoulder' then X := 0.7;
      Put(Obj(Ref,Key),'x',TJSONNumber.Create(C.Document.Width*X)); Put(Obj(Ref,Key),'y',TJSONNumber.Create(C.Document.Height*0.37));
    end;
    Put(Ref,'upperBodyBottomY',TJSONNumber.Create(C.Document.Height*0.65)); Put(C.Settings,'motionReference',Ref);
    C.Production.Free; C.Production := CheckPsdProduction(C); var Reason: string;
    Check(PsdReadyForScript(C,Reason),'all functional conditions plus valid test reference allow completion');
    var BlinkGroup := C.Document.FindLayer(S(Obj(Obj(C.Settings,'animation'),'blink'),'groupId')); var Opacity := BlinkGroup.Opacity; BlinkGroup.Opacity := 0;
    Report := CheckPsdProduction(C); try Check(not PassedCheck(Report,'blink'),'valid but invisible eye layers cannot satisfy functional blink'); finally Report.Free; end; BlinkGroup.Opacity := Opacity;
    SaveCharacter(C,W,Path); Session := TPsdSession.Create(Root,False); var A := Args(Session); A.AddPair('path',Path); Run(Session,'open',A);
    Check(Session.CompletedEditSession,'reopened complete character enters explicit-save editing mode');
    var ReadinessChecks := Session.ReadinessChecks; var Status := Session.Status;
    try Check(B(Status,'readyForScript') and (Session.ReadinessChecks=ReadinessChecks),'unchanged status reuses the fully validated completion result'); finally Status.Free; end;
    var Before := THashSHA2.GetHashStringFromFile(Path); A := Args(Session); A.AddPair('name','明示保存の検証'); Run(Session,'set-info',A);
    Check(Session.Dirty and (THashSHA2.GetHashStringFromFile(Path)=Before),'complete edit does not autosave or change saved bytes');
    Status := Session.Status;
    try Check(not B(Status,'readyForScript') and (Session.ReadinessChecks>ReadinessChecks),'editing invalidates cached readiness and blocks new script selection'); finally Status.Free; end;
    Run(Session,'save',Args(Session)); Check(not Session.Dirty and (THashSHA2.GetHashStringFromFile(Path)<>Before),'explicit save persists completed-session edit');
    A := Args(Session); A.AddPair('path',Path); Run(Session,'open',A); Check(Session.Character.Name='明示保存の検証','saved edit survives reopening');
    Check(THashSHA2.GetHashStringFromFile(Original)=OriginalHash,'user original registration remains unchanged');
    TFile.WriteAllText(TPath.Combine(Root,'result.txt'),'PASS TOTAL: '+Passed.ToString,TEncoding.UTF8); Writeln('PASS TOTAL: '+Passed.ToString); Writeln('ARTIFACT ROOT: '+Root);
  finally Session.Free; C.Free; W.Free; end;
end;
begin try Tests; except on E: Exception do begin Writeln(E.ClassName+': '+E.Message); ExitCode := 1; end; end;
end.
