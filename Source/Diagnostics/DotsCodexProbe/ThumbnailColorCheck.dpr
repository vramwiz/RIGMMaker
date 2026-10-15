program ThumbnailColorCheck;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash,
  Winapi.Windows, Vcl.Imaging.pngimage, RigmThumbnailCache, ArtPng;
var Checks: TJSONArray; Report: TJSONObject;
procedure Check(Value: Boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
  Checks.Add(Message);
end;
function PixelDifferences(const FileName: string; Width,Height: Integer; const Pixels: TBytes): Integer;
begin
  var Png := TPngImage.Create;
  try
    Png.LoadFromFile(FileName);
    Check((Png.Width=Width) and (Png.Height=Height),'PNG dimensions equal source');
    Result := 0;
    for var Y := 0 to Height-1 do for var X := 0 to Width-1 do begin
      var Colour := Png.Pixels[X,Y]; var Index := (Y*Width+X)*4;
      var Alpha := Png.AlphaScanline[Y];
      if (GetRValue(Colour)<>Pixels[Index]) or (GetGValue(Colour)<>Pixels[Index+1]) or
        (GetBValue(Colour)<>Pixels[Index+2]) or (Alpha=nil) or (Alpha[X]<>Pixels[Index+3]) then Inc(Result);
    end;
  finally Png.Free; end;
end;
function AwaitReference(Cache: TRigmThumbnailCache; const Path: string): string;
begin
  var Deadline := GetTickCount64+20000;
  repeat
    Result := Cache.ReferencePng(Path);
    if Result<>'' then Exit;
    Sleep(10); CheckSynchronize(0);
  until GetTickCount64>Deadline;
  raise Exception.Create('Character reference timed out.');
end;
begin
  Checks := TJSONArray.Create; Report := TJSONObject.Create;
  try
    try
      var Root := ParamStr(1); var Relative := ParamStr(2); var Output := ParamStr(3);
      if FileExists(TPath.Combine(Output,'result.json')) then raise Exception.Create('Fresh output required.');
      ForceDirectories(Output);
      var Pixels: TBytes := [255,0,0,255, 0,255,0,255, 0,0,255,255,
        255,210,60,128, 220,160,130,64, 10,30,70,0];
      var Synthetic := TPath.Combine(Output,'rgba-colours.png');
      WriteRgbaPng(Synthetic,3,2,Pixels);
      Check(PixelDifferences(Synthetic,3,2,Pixels)=0,'independent PNG pixels preserve red green blue hair skin and alpha');
      var Source := TPath.Combine(Root,Relative); var SourceHash := THashSHA2.GetHashStringFromFile(Source);
      var Cache := TRigmThumbnailCache.Create(Root); var Reference := '';
      try
        Reference := AwaitReference(Cache,Relative); var Entry := Cache.Request(Relative);
        Check(Entry<>nil,'actual character cache ready');
        Check(PixelDifferences(Reference,Entry.Width,Entry.Height,Entry.Pixels)=0,'actual character reference preserves every RGBA pixel');
        Check(Cache.ReferencePng(Source)=Reference,'absolute and relative character paths share the corrected reference');
        var Old := TPath.Combine(Root,'Cache\ScriptThumbnailRefs\'+THashSHA2.GetHashString(Source+'|'+Entry.Signature)+'.png');
        Check(not SameText(Reference,Old),'v2 cache key cannot reuse old reversed-colour PNG');
        if FileExists(Old) then begin
          var Changed := PixelDifferences(Old,Entry.Width,Entry.Height,Entry.Pixels);
          Check(Changed>0,'old cached PNG reproduces the colour corruption');
          Report.AddPair('oldMismatchedPixels',TJSONNumber.Create(Changed)); Report.AddPair('oldReferencePath',Old);
        end;
        Report.AddPair('width',TJSONNumber.Create(Entry.Width)); Report.AddPair('height',TJSONNumber.Create(Entry.Height));
      finally Cache.Free; end;
      var Hash := THashSHA2.GetHashStringFromFile(Reference); var Modified := TFile.GetLastWriteTimeUtc(Reference);
      Cache := TRigmThumbnailCache.Create(Root);
      try
        Check(AwaitReference(Cache,Relative)=Reference,'warm disk cache returns the same corrected reference');
        Check((Hash=THashSHA2.GetHashStringFromFile(Reference)) and (Modified=TFile.GetLastWriteTimeUtc(Reference)),
          'repeated reference requests do not rewrite or duplicate PNG');
      finally Cache.Free; end;
      Check(SourceHash=THashSHA2.GetHashStringFromFile(Source),'original character file unchanged');
      Report.AddPair('referencePath',Reference); Report.AddPair('referenceSha256',Hash);
      Report.AddPair('success',TJSONBool.Create(True));
    except on E: Exception do begin Report.AddPair('success',TJSONBool.Create(False)); Report.AddPair('error',E.Message); ExitCode := 1; end; end;
    Report.AddPair('checks',Checks); Checks := nil;
    TFile.WriteAllText(TPath.Combine(ParamStr(3),'result.json'),Report.ToJSON,TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally Report.Free; Checks.Free; end;
end.
