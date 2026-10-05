program PsdVerifyRegistered;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, System.JSON, System.Hash,
  PsdJson, PsdWorkspace, PsdPackage, PsdCharacter, PsdAnimation, ArtDocument, ArtPng;

procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create('FAIL: ' + Name); Writeln('PASS: ' + Name); end;
function Equal(const A, B: TBytes): Boolean;
begin Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A))); end;

begin
  try
    if ParamCount <> 1 then raise Exception.Create('Usage: PsdVerifyRegistered <data-root>');
    var W := TPsdWorkspace.Create(ParamStr(1)); var C: TPsdCharacter := nil;
    var R: TPsdRenderer := nil; var Parts: TJSONValue := nil; var Prepared: TJSONValue := nil;
    try
      W.Initialize; C := LoadCharacter(W, 'Characters\blonde-android-20261005.psdchar');
      Parts := Parse(W.ReadText('Work\金髪アンドロイド-20261005\data\parts.json'));
      var Count := 0;
      for var V in TJSONArray(Parts) do begin
        var P := TJSONObject(V); var L := C.Document.FindLayer(S(P, 'id'));
        var PNG := ReadPng(W.Resolve('Work\金髪アンドロイド-20261005\' + S(P, 'file')));
        Check((L <> nil) and Equal(L.Pixels, PNG.Pixels) and
          (L.Bounds.Left = I(Obj(P, 'placement'), 'left')) and (L.Bounds.Top = I(Obj(P, 'placement'), 'top')) and
          (L.Bounds.Width = PNG.Width) and (L.Bounds.Height = PNG.Height), 'original layer RGBA/placement: ' + S(P, 'id'));
        if B(P, 'referenceOnly') then Check(not L.Visible, 'original reference remains hidden') else Inc(Count);
      end;
      Check(Count = 51, 'all 51 original editable layers retained');
      Check(Obj(C.Settings, 'expressions').Count = 8, 'six original and two existing-part expression combinations');
      Check(S(Obj(Obj(C.Settings, 'expressions'), '哀しみ'), 'productionMethod') = 'existing-layer-combination', 'sadness is existing-part combination');
      Check(S(Obj(Obj(C.Settings, 'expressions'), '解説'), 'productionMethod') = 'existing-layer-combination', 'explanation is existing-part combination');
      Check(Obj(C.Settings, 'gaze').Count = 6, 'front plus five screen-space gazes');
      Check(Arr(C.Settings, 'nonFront').Count = 2, 'two full-body non-front poses');
      Check(Arr(C.Settings, 'assetHistory').Count = 7, 'seven new drawings carry provenance');
      Prepared := Parse(W.ReadText('Work\PsdGenerated-20261005\prepared-assets.json'));
      for var V in TJSONArray(Prepared) do begin
        var P := TJSONObject(V); var Found := False;
        for var H in Arr(C.Settings, 'assetHistory') do begin
          var O := TJSONObject(H); if not SameText(S(O, 'sha256'), S(P, 'sha256')) then Continue;
          Found := True; var L := C.Document.FindLayer(S(O, 'assetId')); var PNG := ReadPng(W.Resolve(S(P, 'output')));
          Check((L <> nil) and Equal(L.Pixels, PNG.Pixels) and (L.Bounds.Left = I(P, 'x')) and (L.Bounds.Top = I(P, 'y')), 'new drawing pixels/position: ' + S(P, 'key'));
          Check(B(O, 'newDrawing') and (S(O, 'visualState') = 'pending-user-review') and
            SameText(THashSHA2.GetHashStringFromFile(W.Resolve(S(O, 'rawSourcePath'))), S(O, 'rawSourceSha256')), 'new drawing origin/review state: ' + S(P, 'key'));
        end;
        Check(Found, 'new drawing is registered: ' + S(P, 'key'));
      end;
      R := TPsdRenderer.Create(C, W, 0); var State := TPsdFrameState.Default;
      State.AutoBlink := False; State.Motion := 'none';
      var Neutral := R.Composite(State); var Old := ReadPng(W.Resolve('Characters\blonde-android-20261005-neutral.png'));
      Check(Equal(Neutral, Old.Pixels), 'normal composite identical to original registration');
      for var Key in ['left', 'left-up', 'up', 'right-up', 'right'] do begin
        State.Gaze := Key; Check(not Equal(Neutral, R.Composite(State)), 'gaze changes visible composite: ' + Key);
      end;
      for var P in Arr(C.Settings, 'nonFront') do begin
        State.NonFrontId := S(TJSONObject(P), 'id'); State.Expression := '喜び'; State.AutoBlink := True; State.Seconds := 3.9;
        State.HasPhoneme := True; State.Phoneme := 'a'; var A := R.Composite(State); var Choices := R.Choices(State);
        try Check(Choices.Count = 0, 'non-front has no facial choices'); finally Choices.Free; end;
        State.Expression := '怒り'; State.Phoneme := 'o'; State.Seconds := 0;
        Check(Equal(A, R.Composite(State)), 'non-front ignores expression/blink/phoneme');
      end;
      var Portable := TPsdWorkspace.Create(TPath.Combine(ExtractFilePath(ParamStr(0)), 'PortableCheck\' + NewId));
      var Copy: TPsdCharacter := nil; var Again: TPsdRenderer := nil;
      try
        Portable.Initialize; TFile.Copy(W.Resolve('Characters\blonde-android-20261005.psdchar'), Portable.Resolve('Characters\only.psdchar', False));
        Copy := LoadCharacter(Portable, 'Characters\only.psdchar'); Again := TPsdRenderer.Create(Copy, Portable, 0);
        State := TPsdFrameState.Default; State.AutoBlink := False; State.Motion := 'none';
        Check(Equal(Neutral, Again.Composite(State)), 'single package renders without original Work/input files');
        State.NonFrontId := S(TJSONObject(Arr(Copy.Settings, 'nonFront')[1]), 'id');
        Check(Length(Again.Frame(State)) = 1920 * 1080 * 4, 'portable package renders non-front FullHD');
      finally Again.Free; Copy.Free; Portable.Free; end;
      Writeln('REGISTERED MATERIAL VALIDATION PASSED');
    finally Prepared.Free; Parts.Free; R.Free; C.Free; W.Free; end;
  except on E: Exception do begin Writeln(E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
