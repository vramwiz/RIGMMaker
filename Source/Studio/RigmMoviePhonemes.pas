unit RigmMoviePhonemes;

interface
function MoviePhonemeMouth(const LabPath: string; Seconds: Double; out Available: Boolean): Double;
function MoviePhonemeSample(const LabPath: string; Seconds: Double; out Phone: string; out Available: Boolean): Double;

implementation
uses System.SysUtils, System.Classes, System.IOUtils, System.Math, System.Generics.Collections;
type
  TPhoneme = record Start,Finish,Open: Double; Phone: string; end;
  TPhonemeTrack = class
  public
    Stamp: string;
    Segments: TArray<TPhoneme>;
  end;
var Tracks: TObjectDictionary<string,TPhonemeTrack>; Guard: TObject;
function Openness(const Phone: string): Double;
begin
  if SameText(Phone,'a') then Exit(1);
  if SameText(Phone,'i') then Exit(0.4);
  if SameText(Phone,'u') then Exit(0.3);
  if SameText(Phone,'e') then Exit(0.7);
  if SameText(Phone,'o') then Exit(0.8);
  if SameText(Phone,'N') then Exit(0.15);
  Result := 0; // Pauses and consonants retain the exact LAB boundaries.
end;
function MoviePhonemeMouth(const LabPath: string; Seconds: Double; out Available: Boolean): Double;
begin var Phone: string; Result := MoviePhonemeSample(LabPath,Seconds,Phone,Available); end;
function MoviePhonemeSample(const LabPath: string; Seconds: Double; out Phone: string; out Available: Boolean): Double;
var Track: TPhonemeTrack; First,Last,Middle: Integer;
begin
  Result := 0; Available := False; Phone := '';
  if (LabPath='') or not FileExists(LabPath) then Exit;
  var Stamp := TFile.GetSize(LabPath).ToString+'|'+FormatDateTime('yyyymmddhhnnsszzz',TFile.GetLastWriteTimeUtc(LabPath));
  TMonitor.Enter(Guard);
  try
    if not Tracks.TryGetValue(LabPath,Track) or (Track.Stamp<>Stamp) then begin
      if TFile.GetSize(LabPath)>4*1024*1024 then Exit;
      var Lines := TStringList.Create; var Values := TList<TPhoneme>.Create;
      try
        Lines.Text := TFile.ReadAllText(LabPath,TEncoding.UTF8);
        if Lines.Count>20000 then Exit;
        var Valid := True; var Previous: Int64 := 0;
        for var Line in Lines do begin
          var Fields := Line.Trim.TrimLeft([#$FEFF]).Split([' ',#9],TStringSplitOptions.ExcludeEmpty); if Length(Fields)=0 then Continue;
          var A,B: Int64;
          if (Length(Fields)<>3) or not TryStrToInt64(Fields[0],A) or not TryStrToInt64(Fields[1],B) or (A<0) or (B<=A) or (A<Previous) then begin Valid := False; Break; end;
          var V: TPhoneme; V.Start := A/10000000.0; V.Finish := B/10000000.0; V.Phone := Fields[2]; V.Open := Openness(Fields[2]); Values.Add(V); Previous := B;
        end;
        if not Valid or (Values.Count=0) then Exit;
        Track := TPhonemeTrack.Create; Track.Stamp := Stamp; Track.Segments := Values.ToArray;
        if Tracks.Count>=64 then Tracks.Clear;
        Tracks.AddOrSetValue(LabPath,Track);
      finally Values.Free; Lines.Free; end;
    end;
    Available := True; First := 0; Last := High(Track.Segments);
    while First<=Last do begin
      Middle := (First+Last) div 2;
      if Seconds<Track.Segments[Middle].Start then Last := Middle-1
      else if Seconds>=Track.Segments[Middle].Finish then First := Middle+1
      else begin Phone := Track.Segments[Middle].Phone; Exit(Track.Segments[Middle].Open); end;
    end;
  finally TMonitor.Exit(Guard); end;
end;
initialization
  Guard := TObject.Create; Tracks := TObjectDictionary<string,TPhonemeTrack>.Create([doOwnsValues]);
finalization
  Tracks.Free; Guard.Free;
end.
