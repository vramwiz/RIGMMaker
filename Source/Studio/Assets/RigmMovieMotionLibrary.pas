// 既存RIGMから生成した全体モーションを保存・読込する。キャラクターのハッシュごとに素材を分離する。
unit RigmMovieMotionLibrary;
interface
uses System.JSON;
function LoadCharacterMotions(const CharacterFile: string): TJSONObject;
function BuildCharacterMotions(const CharacterFile: string): TJSONObject;
implementation
uses System.SysUtils, System.IOUtils, System.Hash, System.Math, System.StrUtils, Vcl.Imaging.pngimage,
  RigmStorage, RigmModel, RigmRenderer, RigmMovieActing, RigmJson, RigmAppSettings;
function Directory(const CharacterFile: string): string;
begin
  Result := TPath.Combine(TPath.Combine(AppSettings.Root,'Characters'),THashSHA2.GetHashStringFromFile(CharacterFile));
  Result := TPath.Combine(Result,'Motions');
end;
function LoadCharacterMotions(const CharacterFile: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  if not FileExists(CharacterFile) then Exit;
  var Path := TPath.Combine(Directory(CharacterFile),'presets.json'); if not FileExists(Path) then Exit;
  if TFile.GetSize(Path)>1024*1024 then raise ERigm.Create('Character motion library is too large');
  var Stored := ParseObject(TFile.ReadAllText(Path,TEncoding.UTF8));
  var ContentWidth := 0; var ContentHeight := 0; var Margin := 0;
  try
    for var Pair in JO(Stored,'motions') do begin
      var Motion := Pair.JsonValue.Clone as TJSONObject;
      try
        for var V in JA(Motion,'frames') do begin
          var Frame := TJSONObject(V); var Image := TPath.GetFullPath(TPath.Combine(Directory(CharacterFile),JS(Frame,'image')));
          if not FileExists(Image) then raise ERigm.Create('Stored character motion image is missing');
          Frame.RemovePair('image').Free; Frame.AddPair('image',Image);
        end;
        // Upgrade legacy generator metadata in memory without rewriting the shared library.
        if (JN(Motion,'contentWidth')<=0) and StartsText('whole-character transforms rendered from existing RIGM',JS(Motion,'provenance')) then begin
          if ContentWidth=0 then begin
            var Doc := LoadRigm(CharacterFile);
            try
              var K := Min(1.0,700/Max(Doc.Art.Width,Doc.Art.Height));
              ContentWidth := Max(1,Round(Doc.Art.Width*K)); ContentHeight := Max(1,Round(Doc.Art.Height*K));
              Margin := Max(40,Max(ContentWidth,ContentHeight) div 8);
            finally Doc.Free; end;
          end;
          AddN(Motion,'canvasWidth',ContentWidth+Margin*2); AddN(Motion,'canvasHeight',ContentHeight+Margin*2);
          AddN(Motion,'contentWidth',ContentWidth); AddN(Motion,'contentHeight',ContentHeight);
          AddN(Motion,'anchorX',Margin+ContentWidth/2); AddN(Motion,'anchorY',Margin+ContentHeight);
        end;
        Result.AddPair(Pair.JsonString.Value,Motion); Motion := nil;
      finally Motion.Free; end;
    end;
  except Result.Free; raise; end;
  Stored.Free;
end;
function BuildCharacterMotions(const CharacterFile: string): TJSONObject;
const Names: array[0..3] of string = ('happy','sad','angry','gentle');
var Doc: TRigmDocument; Pose: TRigmPose; Acting: TRigmMovieActing; W,H: Integer;
begin
  if not FileExists(CharacterFile) then raise ERigm.Create('Select an existing character first');
  var Root := Directory(CharacterFile); ForceDirectories(Root);
  if FileExists(TPath.Combine(Root,'presets.json')) then Exit(LoadCharacterMotions(CharacterFile));
  Doc := LoadRigm(CharacterFile); Pose := TRigmPose.Create; Acting := TRigmMovieActing.Create;
  var Stored := TJSONObject.Create; var Motions := TJSONObject.Create; Stored.AddPair('motions',Motions);
  try
    Pose.Reset; Acting.ApplyFeatureAssets(Doc,Pose,0,1);
    var Pixels := RenderRigm(Doc,Pose,700,W,H); var Margin := Max(40,Max(W,H) div 8);
    var OW := W+Margin*2; var OH := H+Margin*2;
    for var Kind := 0 to High(Names) do begin
      var Motion := TJSONObject.Create; var Frames := TJSONArray.Create; Motion.AddPair('frames',Frames);
      AddB(Motion,'loop',True); Motion.AddPair('provenance','whole-character transforms rendered from existing RIGM; no generated character artwork');
      AddN(Motion,'canvasWidth',OW); AddN(Motion,'canvasHeight',OH);
      AddN(Motion,'contentWidth',W); AddN(Motion,'contentHeight',H);
      AddN(Motion,'anchorX',Margin+W/2); AddN(Motion,'anchorY',Margin+H);
      Motions.AddPair(Names[Kind],Motion);
      for var Index := 0 to 11 do begin
        var Phase := Index/12*Pi*2; var Angle := Sin(Phase)*4*Pi/180; var DX := Sin(Phase)*14; var DY := 0.0;
        if Kind=0 then begin Angle := Sin(Phase)*6*Pi/180; DY := -Abs(Sin(Phase))*26; end;
        if Kind=1 then begin Angle := Sin(Phase)*3*Pi/180; DY := Abs(Sin(Phase))*9; end;
        if Kind=2 then begin Angle := Sin(Phase*2)*2*Pi/180; DX := Sin(Phase*2)*20; end;
        if Kind=3 then begin Angle := Sin(Phase)*3.5*Pi/180; DX := Sin(Phase)*9; end;
        var Png := TPngImage.CreateBlank(COLOR_RGBALPHA,8,OW,OH);
        try
          var C := Cos(Angle); var S := Sin(Angle);
          for var Y := 0 to OH-1 do begin
            var Row := PByte(Png.Scanline[Y]); var Alpha := PByte(Png.AlphaScanline[Y]);
            for var X := 0 to OW-1 do begin
              var TX := X-(Margin+W/2)-DX; var TY := Y-(Margin+H)-DY;
              var SX := Round(C*TX+S*TY+W/2); var SY := Round(-S*TX+C*TY+H);
              Alpha[X] := 0;
              if (SX>=0) and (SX<W) and (SY>=0) and (SY<H) then begin
                var Q := (SY*W+SX)*4;
                for var Channel := 0 to 2 do Row[X*3+2-Channel] := Pixels[Q+Channel];
                Alpha[X] := Pixels[Q+3];
              end;
            end;
          end;
          var Name := Names[Kind]+'-'+Index.ToString+'.png'; var Path := TPath.Combine(Root,Name);
          if not FileExists(Path) then Png.SaveToFile(Path);
          var Frame := TJSONObject.Create; Frame.AddPair('image',Name); AddN(Frame,'duration',0.125); Frames.AddElement(Frame);
        finally Png.Free; end;
      end;
    end;
    Stored.AddPair('characterId',Doc.FileId); Stored.AddPair('sourceSha256',THashSHA2.GetHashStringFromFile(CharacterFile));
    var Temp := TPath.Combine(Root,'presets-'+TGUID.NewGuid.ToString+'.tmp');
    TFile.WriteAllText(Temp,Stored.ToJSON,TEncoding.UTF8); TFile.Move(Temp,TPath.Combine(Root,'presets.json'));
  finally Stored.Free; Acting.Free; Pose.Free; Doc.Free; end;
  Result := LoadCharacterMotions(CharacterFile);
end;
end.
