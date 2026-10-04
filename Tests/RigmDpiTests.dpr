program RigmDpiTests;
{$APPTYPE CONSOLE}
{$R '..\RIGMMaker.res'}
uses System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.Graphics,
  Vcl.Themes, Vcl.Styles, Vcl.Imaging.pngimage, Winapi.Windows, Winapi.CommCtrl,
  RIGMMakerMainForm, RigmEditorForm, RigmMovieForm, RigmMovieSession, RigmJson, ArtLayerList;
var Count: Integer; Checks: TJSONArray; Directory: string;
procedure Check(OK: Boolean; const Name: string);
begin if not OK then raise Exception.Create('FAIL: '+Name); Inc(Count); Checks.Add(Name); Writeln('PASS: '+Name); end;
function Find(P: TWinControl; const Name: string): TControl;
begin
  Result := nil;
  for var I := 0 to P.ControlCount-1 do begin
    var C := P.Controls[I]; if C.Name=Name then Exit(C);
    if C is TWinControl then begin Result := Find(TWinControl(C),Name); if Result<>nil then Exit; end;
  end;
end;
function TextFits(L: TLabel): Boolean;
begin
  var B := Vcl.Graphics.TBitmap.Create;
  try
    B.Canvas.Font.Assign(L.Font); var R := Rect(0,0,L.Width,0);
    DrawText(B.Canvas.Handle,PChar(L.Caption),Length(L.Caption),R,DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Result := (R.Height<=L.Height) and (L.Left+L.Width<=L.Parent.ClientWidth);
  finally B.Free; end;
end;
procedure Capture(F: TForm; const Name: string);
begin
  var B := Vcl.Graphics.TBitmap.Create; var P := TPngImage.Create;
  try B.SetSize(F.ClientWidth,F.ClientHeight); F.PaintTo(B.Canvas.Handle,0,0);
    P.Assign(B); P.SaveToFile(TPath.Combine(Directory,Name+'.png'));
  finally P.Free; B.Free; end;
end;
procedure CheckBar(F: TForm; const Name: string; PPI: Integer);
begin
  var Bar := TToolBar(Find(F,Name));
  Check((Bar.Images.Width=MulDiv(24,PPI,96)) and (Bar.ButtonWidth=MulDiv(40,PPI,96)),Name+' icon metrics '+PPI.ToString);
  for var I := 0 to Bar.ButtonCount-1 do if Bar.Buttons[I].Visible and (Bar.Buttons[I].Style<>tbsSeparator) then begin
    var R: TRect; Check(Bar.Perform(TB_GETITEMRECT,I,LPARAM(@R))<>0,Name+' native rectangle '+I.ToString+' '+PPI.ToString);
    var H: TPoint; H := Point((R.Left+R.Right) div 2,(R.Top+R.Bottom) div 2);
    Check(Bar.Perform(TB_HITTEST,0,LPARAM(@H))=I,Name+' native hit '+I.ToString+' '+PPI.ToString);
  end;
end;
procedure Run;
begin
  Application.Initialize; TStyleManager.TrySetStyle('Windows Modern Dark');
  var L := TMainForm.Create(nil);
  var E := TRigmEditorForm.Create(nil);
  var S := TRigmMovieSession.Create; var M := TRigmMovieForm.CreateForSession(nil,S);
  try
    L.Show; E.OpenSample; E.Show; M.Show; Application.ProcessMessages;
    for var PPI in [96,120,144,192,144,96] do begin
      L.ScaleForPPI(PPI); E.ScaleForPPI(PPI); M.ScaleForPPI(PPI);
      L.Width := MulDiv(1120,PPI,96); L.Height := MulDiv(760,PPI,96);
      Application.ProcessMessages;
      Check(L.ScaleValue(96)=PPI,'main layout scale '+PPI.ToString);
      Check(Abs(Abs(L.Font.Height)-MulDiv(13,PPI,96))<=1,'main 10 point font '+PPI.ToString);
      Check(TextFits(TLabel(Find(L,'LibraryTitle'))),'unclipped main title '+PPI.ToString);
      Check(TextFits(TLabel(Find(L,'LibraryDescription'))),'unclipped description '+PPI.ToString);
      Check(TextFits(TLabel(Find(L,'LibraryStatus'))),'unclipped save directory '+PPI.ToString);
      Check(TextFits(TLabel(Find(L,'LibraryGuide'))),'scrollable full guide '+PPI.ToString);
      Check(TListView(Find(L,'CharacterLibrary')).SmallImages.Width=MulDiv(128,PPI,96),'thumbnail DPI '+PPI.ToString);
      CheckBar(L,'LibraryToolbar',PPI); CheckBar(E,'EditorToolbar',PPI); CheckBar(M,'MovieToolbar',PPI);
      // Rebuild dynamic fields at the new DPI through a real selection change.
      E.Editor.SelectedId := E.Editor.Document.Layers[1].Id;
      var Args := TJSONObject.Create;
      try Args.AddPair('id',E.Editor.SelectedId); var Reply := E.Editor.Execute('select-object',Args); Reply.Free; finally Args.Free; end;
      var Field := TEdit(Find(E,'Fieldname'));
      Check((Field<>nil) and (Field.Left=MulDiv(12,PPI,96)) and (Field.Width=MulDiv(328,PPI,96)),
        'dynamic field geometry '+PPI.ToString);
      Check(Abs(Field.Font.Height)=Abs(E.Font.Height),'dynamic field font '+PPI.ToString);
      var Layers := TArtLayerList(Find(E,'LayerList')); Layers.EditEnabled := True; Layers.ScrollBar.Position := 0;
      var Slider := Layers.SliderAt(0);
      if Slider=nil then Writeln('ROW slider unavailable; edit=',Layers.EditEnabled,' rows=',Layers.RowCount)
      else Writeln('ROW slider: ppi=',PPI,' top=',Slider.Top,' height=',Slider.Height);
      Check((Slider<>nil) and (Slider.Height=MulDiv(28,PPI,96)) and
        (Slider.Top=MulDiv(50,PPI,96)),'layer row slider geometry '+PPI.ToString);
      Check(Layers.ScrollBar.SmallChange=MulDiv(88,PPI,96),'layer row scrolling scale '+PPI.ToString);
      var Character := TEdit(Find(M,'MovieCharacterPath'));
      Check((Character<>nil) and (Abs(Character.Left-MulDiv(722,PPI,96))<=1), 'movie field geometry '+PPI.ToString);
      Capture(L,'library-'+PPI.ToString); Capture(E,'editor-'+PPI.ToString); Capture(M,'movie-'+PPI.ToString);
    end;
    L.ScaleForPPI(192); L.Constraints.MinWidth := 0; L.Constraints.MinHeight := 0;
    L.Width := 1120; L.Height := 760; Application.ProcessMessages;
    Check(TextFits(TLabel(Find(L,'LibraryTitle'))) and TextFits(TLabel(Find(L,'LibraryStatus'))),
      'literal 1120x760 high DPI title and save directory');
    Capture(L,'library-192-1120x760');
  finally M.Free; S.Free; E.Free; L.Free; end;
end;
begin
  Directory := TPath.Combine(ExtractFilePath(ParamStr(0)),'Dpi'); ForceDirectories(Directory); Checks := TJSONArray.Create;
  try
    try Run; except on E: Exception do begin Writeln(E.Message); Checks.Add(E.Message); ExitCode := 1; end; end;
    var O := TJSONObject.Create;
    try AddN(O,'passed',Count); AddB(O,'success',ExitCode=0); AddB(O,'physicalMonitorTransitionVerified',False);
      O.AddPair('captureMethod','isolated VCL PaintTo; simulated ScaleForPPI transitions');
      O.AddPair('checks',Checks); Checks := nil; TFile.WriteAllText(TPath.Combine(Directory,'results.json'),O.ToJSON,TEncoding.UTF8);
    finally O.Free; end;
    Writeln(Count,' DPI checks passed');
  finally Checks.Free; end;
end.
