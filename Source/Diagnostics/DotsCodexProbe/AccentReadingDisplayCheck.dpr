program AccentReadingDisplayCheck;
{$APPTYPE CONSOLE}
// 所有フォームだけで読みの確定・取消・保存再表示と実描画画素を検査する。引数は出力先。
uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.Graphics, Vcl.Imaging.pngimage, SerifVoicevoxAccentView, AviUtl2StyleColors,
  PsdJson, RigmJson;
type
  TAccentPaintAccess = class(TSerifVoicevoxAccentPaintControl);
  TReadingProbe = class
    Query: string;
    Changes: Integer;
    procedure Changed(Sender: TObject; const Value: string);
  end;
var Output,Error: string; Checks: TJSONArray;
procedure TReadingProbe.Changed(Sender: TObject; const Value: string);
begin Query := Value; Inc(Changes); end;
procedure Check(Value: Boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); Checks.Add(Message); Writeln('PASS ',Message); end;
function Capture(Paint: TSerifVoicevoxAccentPaintControl): TBitmap;
begin
  Result := TBitmap.Create; Result.PixelFormat := pf32bit;
  Result.SetSize(Paint.Width,Paint.Height); Paint.PaintTo(Result.Canvas,0,0); GdiFlush;
end;
function SamePixels(A,B: TBitmap; const Area: TRect): Boolean;
begin
  GdiFlush; Result := False;
  for var Y := Area.Top to Area.Bottom-1 do begin
    var XRow := PByte(A.ScanLine[Y]); var YRow := PByte(B.ScanLine[Y]);
    for var X := Area.Left to Area.Right-1 do
      for var Channel := 0 to 2 do if XRow[X*4+Channel]<>YRow[X*4+Channel] then Exit;
  end;
  Result := True;
end;
procedure CheckReadingPixels(Paint: TSerifVoicevoxAccentPaintControl;
  const Labels: array of string; AcousticCount: Integer=3);
begin
  var Actual := Capture(Paint); var Expected := TBitmap.Create;
  try
    Expected.Assign(Actual); var Cells := Paint.MoraCells;
    var Area := Rect(Cells[0].Left,MulDiv(78,Paint.CurrentPPI,96),Min(Paint.Width,Cells[AcousticCount-1].Right),Paint.Height);
    Expected.Canvas.Brush.Color := TAccentPaintAccess(Paint).Color; Expected.Canvas.FillRect(Area);
    Expected.Canvas.Font.Assign(TAccentPaintAccess(Paint).Font); Expected.Canvas.Font.Color := A2SCPanelText;
    Expected.Canvas.Brush.Style := bsClear; var X := Cells[0].Left; var Reading := '';
    for var I := 0 to High(Labels) do begin
      var TextRect := Area;
      if Length(Labels)=AcousticCount then begin TextRect.Left := Cells[I].Left; TextRect.Right := Cells[I].Right; end
      else begin
        TextRect.Left := X;
        TextRect.Right := X+Max(MulDiv(28,Paint.CurrentPPI,96),Expected.Canvas.TextWidth(Labels[I])+MulDiv(6,Paint.CurrentPPI,96));
      end;
      X := TextRect.Right; Reading := Reading+Labels[I];
      DrawText(Expected.Canvas.Handle,PChar(Labels[I]),Length(Labels[I]),TextRect,DT_CENTER or DT_TOP or DT_SINGLELINE or DT_NOPREFIX);
    end;
    Check(SamePixels(Actual,Expected,Area),'committed reading uses centered UI cells: '+Reading);
    var PNG := TPngImage.Create;
    try PNG.Assign(Actual); PNG.SaveToFile(TPath.Combine(Output,'reading-'+Checks.Count.ToString+'.png')); finally PNG.Free; end;
  finally Expected.Free; Actual.Free; end;
end;
function BeginEdit(Paint: TSerifVoicevoxAccentPaintControl): TEdit;
begin
  var Cells := Paint.MoraCells;
  Paint.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam((Cells[0].Left+Cells[0].Right) div 2,MulDiv(85,Paint.CurrentPPI,96)));
  Paint.Perform(WM_LBUTTONUP,0,MakeLParam(Cells[0].Left,MulDiv(85,Paint.CurrentPPI,96)));
  Result := nil;
  for var I := 0 to Paint.ControlCount-1 do if (Paint.Controls[I] is TEdit) and Paint.Controls[I].Visible then Result := Paint.Controls[I] as TEdit;
  Check(Result<>nil,'native click opens the inline reading editor');
end;
procedure Run;
begin
  Output := ParamStr(1); ForceDirectories(Output);
  var Form := TForm.CreateNew(nil); var Probe := TReadingProbe.Create;
  try
    Form.SetBounds(0,0,1000,250); Form.Font.Name := 'Yu Gothic UI'; Form.Font.Size := 10;
    var Accent := TSerifVoicevoxAccentView.Create(Form); Accent.Parent := Form; Accent.Align := alClient;
    Accent.AutoAnalyze := False; Accent.OnChange := Probe.Changed;
    var Query := PsdJson.ObjectText('{"accent_phrases":[]}');
    try
      for var Text in ['カキク','タチツ'] do begin
        var Phrase := PsdJson.ObjectText('{"moras":[],"accent":1,"pause_mora":null,"is_interrogative":false}');
        JA(Query,'accent_phrases').AddElement(Phrase);
        for var C in Text do JA(Phrase,'moras').AddElement(TJSONObject.Create.AddPair('text',string(C)));
      end;
      Accent.ShowText('表示だけを検証する所有セリフ',1,Query.ToJSON);
      var Paint: TSerifVoicevoxAccentPaintControl := nil;
      for var I := 0 to Accent.ComponentCount-1 do if Accent.Components[I] is TSerifVoicevoxAccentPaintControl then Paint := Accent.Components[I] as TSerifVoicevoxAccentPaintControl;
      Check(Paint<>nil,'owned accent view exposes its native paint control');
      Form.Show; ShowWindow(Form.Handle,SW_SHOWNOACTIVATE); Form.Update;
      var Original := Capture(Paint);
      try
        var OriginalWidth := Accent.ContentWidth; var Cells := Paint.MoraCells;
        var Edit := BeginEdit(Paint); Edit.Text := 'サシス'; Edit.Perform(WM_KEYDOWN,VK_RETURN,0);
        Check(not Edit.Visible and (Probe.Changes=1),'Enter commits the reading exactly once');
        var Saved := PsdJson.ObjectText(Probe.Query);
        try
          Check(JS(TJSONObject(JA(Saved,'accent_phrases')[0]),'_rigm_pending_reading')='サシス','internal pending reading contains the edit');
          for var I := 0 to 1 do Check(JA(TJSONObject(JA(Saved,'accent_phrases')[I]),'moras').ToJSON=JA(TJSONObject(JA(Query,'accent_phrases')[I]),'moras').ToJSON,
            'display update preserves acoustic mora data for phrase '+I.ToString);
        finally Saved.Free; end;
        CheckReadingPixels(Paint,['サ','シ','ス']);
        var Updated := Capture(Paint);
        try
          Check(SamePixels(Original,Updated,Rect(0,0,Original.Width,MulDiv(74,Paint.CurrentPPI,96))),'reading edit leaves accent graph pixels unchanged');
          var Area := Rect(Cells[3].Left,MulDiv(78,Paint.CurrentPPI,96),Cells[5].Right,Paint.Height);
          Check(SamePixels(Original,Updated,Area),'other phrase keeps its original reading labels');
          var Before := Probe.Query; Edit := BeginEdit(Paint);
          Check(Edit.Text='サシス','reopening the editor shows the committed reading');
          Edit.Text := '取消する読み'; Edit.Perform(WM_KEYDOWN,VK_ESCAPE,0);
          Check((Probe.Query=Before) and (Probe.Changes=1),'Escape keeps the committed query');
          var Cancelled := Capture(Paint);
          try Check(SamePixels(Updated,Cancelled,Updated.Canvas.ClipRect),'Escape keeps the committed display'); finally Cancelled.Free; end;
        finally Updated.Free; end;
        var LongReading := 'ながいよみにへんこうしてもさいごまですべてひょうじします';
        Edit := BeginEdit(Paint); Edit.Text := LongReading; Edit.OnExit(Edit);
        Check((Probe.Changes=2) and not Edit.Visible,'focus loss commits a new reading exactly once');
        Check(Accent.ContentWidth>OriginalWidth,'longer reading expands the horizontal content width');
        Cells := Paint.MoraCells;
        Check((Length(Cells)=6) and (Cells[3].Left>Cells[2].Right),'widened phrase preserves mora count and the next phrase boundary');
        CheckReadingPixels(Paint,['な','が','い','よ','み','に','へ','ん','こ','う','し','て','も','さ','い','ご','ま','で','す','べ','て','ひょ','う','じ','し','ま','す']);
        var Path := TPath.Combine(Output,'saved-query.json'); TFile.WriteAllText(Path,Probe.Query,TEncoding.UTF8);
        Accent.ShowText('',-1,''); Accent.ShowText('表示だけを検証する所有セリフ',1,TFile.ReadAllText(Path,TEncoding.UTF8));
        CheckReadingPixels(Paint,['な','が','い','よ','み','に','へ','ん','こ','う','し','て','も','さ','い','ご','ま','で','す','べ','て','ひょ','う','じ','し','ま','す']);
        Edit := BeginEdit(Paint); Check(Edit.Text=LongReading,'saved query reopens with the full reading');
        Edit.Perform(WM_KEYDOWN,VK_ESCAPE,0);
        var LongPhrase := Query.Clone as TJSONObject;
        try
          var Phrase := TJSONObject(JA(LongPhrase,'accent_phrases')[0]);
          for var I := 1 to 97 do JA(Phrase,'moras').AddElement(JA(Phrase,'moras')[0].Clone as TJSONObject);
          PsdJson.Put(Phrase,'_rigm_pending_reading','みじかい');
          Accent.ShowText('長い句から短い読みへ',1,LongPhrase.ToJSON);
          CheckReadingPixels(Paint,['み','じ','か','い'],100);
        finally LongPhrase.Free; end;
        var KanaQuery := Query.Clone as TJSONObject;
        try
          var Phrase := TJSONObject(JA(KanaQuery,'accent_phrases')[0]);
          PsdJson.Put(Phrase,'_rigm_pending_reading','キャット');
          var Unchanged := KanaQuery.ToJSON;
          Accent.ShowText('拗音と促音の表示',1,Unchanged);
          CheckReadingPixels(Paint,['キャ','ッ','ト']);
          Check(KanaQuery.ToJSON=Unchanged,'display segmentation never modifies the input query');
          PsdJson.Put(Phrase,'_rigm_pending_reading','か'+#$3099+'キ😀');
          Accent.ShowText('結合濁点とサロゲートペア',1,KanaQuery.ToJSON);
          CheckReadingPixels(Paint,['か'+#$3099,'キ','😀']);
        finally KanaQuery.Free; end;
        Accent.ShowText('表示だけを検証する所有セリフ',1,Query.ToJSON);
        Check(Accent.ContentWidth=OriginalWidth,'resolved query restores normal mora widths');
        var Restored := Capture(Paint);
        try Check(SamePixels(Original,Restored,Original.Canvas.ClipRect),'query without pending reading retains the original per-mora display'); finally Restored.Free; end;
      finally Original.Free; end;
    finally Query.Free; end;
  finally Form.Free; Probe.Free; end;
end;
begin
  Application.Initialize; Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Error := E.ClassName+': '+E.Message; Writeln(Error); ExitCode := 1; end; end;
    if Output<>'' then begin
      var Report := TJSONObject.Create.AddPair('checks',Checks.Clone as TJSONArray).AddPair('error',Error);
      try TFile.WriteAllText(TPath.Combine(Output,'result.json'),Report.ToJSON,TEncoding.UTF8); finally Report.Free; end;
    end;
  finally Checks.Free; end;
end.
