// 区間・音声・キャラクター・場面のタイムラインを描画する。シークと選択はイベントで呼び出し側へ通知する。
unit RigmMovieTimeline;
interface
uses System.Classes, System.JSON, System.Types, Vcl.ExtCtrls, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls;
type
  TRigmMovieTimeline = class(TCustomControl)
  private
    FTimeline, FWaveform: TJSONObject;
    FTime, FOffset, FSpan: Double;
    FOnSeek, FOnSelectCue: TNotifyEvent;
    FSelectedCueId: string;
    FPaintCount: UInt64;
    FStaticBuildCount: UInt64;
    FThumbnailCount: UInt64;
    FCache: TBitmap;
    FCacheDirty: Boolean;
    FContentDirty,FLayoutDragging: Boolean;
    FCachePPI,FCacheFont: Integer;
    FLabelCount,FTextHeight: Integer;
    FHorizontal,FVertical: TScrollBar;
    FUpdatingScroll: Boolean;
    FWheelRemainder: Integer;
    function ViewWidth: Integer;
    function ViewHeight: Integer;
    function RowHeightPixels: Integer;
    function TrackCount: Integer;
    function VisibleSpan: Double;
    procedure UpdateScrollBars;
    procedure ScrollChanged(Sender: TObject);
    procedure PanTo(Offset: Double);
    function SnapTime(Seconds: Double): Double;
    procedure DrawTracks(Target: TCanvas);
    function UiScale(Value: Integer): Integer;
    function PlayheadX: Integer;
    function HeaderWidth: Integer;
    function RulerHeight: Integer;
    function MinimumHeight: Integer;
  protected
    procedure Paint; override;
    procedure Resize; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X,Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetData(Timeline,Waveform: TJSONObject);
    procedure SetTime(Seconds: Double);
    procedure SetSpan(Seconds: Double);
    procedure SelectCue(const CueId: string);
    function SecondsAt(X: Integer): Double;
    procedure WheelAt(Delta: Integer; const Position: TPoint);
    procedure ResetView;
    procedure SetLayoutDragging(Value: Boolean);
    property Time: Double read FTime;
    property OnSeek: TNotifyEvent read FOnSeek write FOnSeek;
    property OnSelectCue: TNotifyEvent read FOnSelectCue write FOnSelectCue;
    property SelectedCueId: string read FSelectedCueId;
    property PaintCount: UInt64 read FPaintCount;
    property StaticBuildCount: UInt64 read FStaticBuildCount;
    property ThumbnailCount: UInt64 read FThumbnailCount;
    property RenderedLabelCount: Integer read FLabelCount;
    property RenderedTextHeight: Integer read FTextHeight;
    property HeaderWidthPixels: Integer read HeaderWidth;
    property RulerHeightPixels: Integer read RulerHeight;
    property MinimumHeightPixels: Integer read MinimumHeight;
  end;
implementation
uses System.SysUtils, System.Math, System.Generics.Collections, Winapi.Windows, RigmJson,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Vcl.Forms;
constructor TRigmMovieTimeline.Create(AOwner: TComponent);
begin
  inherited; DoubleBuffered := True; ControlStyle := ControlStyle+[csOpaque]; FTimeline := TJSONObject.Create; FWaveform := TJSONObject.Create; ShowHint := True; FCache := Vcl.Graphics.TBitmap.Create; FCacheDirty := True; FContentDirty := True;
  FHorizontal := TScrollBar.Create(Self); FHorizontal.Parent := Self; FHorizontal.Kind := sbHorizontal;
  FHorizontal.Name := 'MovieTimelineHorizontal'; FHorizontal.OnChange := ScrollChanged;
  FVertical := TScrollBar.Create(Self); FVertical.Parent := Self; FVertical.Kind := sbVertical;
  FVertical.Name := 'MovieTimelineVertical'; FVertical.OnChange := ScrollChanged;
  Hint := '横トラックをクリックして区間を選択・シーク。選択したセリフを右側で調整します。';
end;
destructor TRigmMovieTimeline.Destroy;
begin FCache.Free; FTimeline.Free; FWaveform.Free; inherited; end;
procedure TRigmMovieTimeline.SetData(Timeline,Waveform: TJSONObject);
begin FTimeline.Free; FWaveform.Free; FTimeline := Timeline.Clone as TJSONObject; FWaveform := Waveform.Clone as TJSONObject;
  FOffset := EnsureRange(FOffset,0.0,Max(0.0,JN(FTimeline,'duration')-VisibleSpan));
  UpdateScrollBars; FCacheDirty := True; FContentDirty := True; Invalidate; end;
function TRigmMovieTimeline.UiScale(Value: Integer): Integer;
begin
  // An embedded form may retain 96 PPI while its outer window is scaled.
  var Host := GetParentForm(Self,True);
  if Host<>nil then Result := Host.ScaleValue(Value) else Result := ScaleValue(Value);
end;
function TRigmMovieTimeline.HeaderWidth: Integer;
begin Result := UiScale(112); end;
function TRigmMovieTimeline.RulerHeight: Integer;
begin Result := UiScale(36); end;
function TRigmMovieTimeline.MinimumHeight: Integer;
begin Result := RulerHeight+RowHeightPixels*4+UiScale(17); end;
function TRigmMovieTimeline.ViewWidth: Integer;
begin Result := Max(1,ClientWidth-UiScale(17)); end;
function TRigmMovieTimeline.ViewHeight: Integer;
begin Result := Max(1,ClientHeight-UiScale(17)); end;
function TRigmMovieTimeline.RowHeightPixels: Integer;
begin Result := UiScale(44); end;
function TRigmMovieTimeline.TrackCount: Integer;
begin
  Result := EnsureRange(JI(FTimeline,'trackCount',4),4,64);
  if FTimeline.GetValue('tracks') is TJSONArray then Result := EnsureRange(JA(FTimeline,'tracks').Count,Result,64);
end;
function TRigmMovieTimeline.VisibleSpan: Double;
begin
  var Duration := Max(0.001,JN(FTimeline,'duration'));
  if FSpan<=0 then Result := Duration else Result := Min(FSpan,Duration);
end;
function TRigmMovieTimeline.SnapTime(Seconds: Double): Double;
begin
  var FPS := Max(1,JN(FTimeline,'fps',30));
  var LastFrame := Max(Int64(0),Ceil(JN(FTimeline,'duration')*FPS)-1);
  Result := EnsureRange(Round(Seconds*FPS),Int64(0),LastFrame)/FPS;
end;
procedure TRigmMovieTimeline.UpdateScrollBars;
begin
  if (FHorizontal=nil) or (FVertical=nil) then Exit;
  FUpdatingScroll := True;
  try
    var Size := UiScale(17);
    FHorizontal.SetBounds(0,ViewHeight,ViewWidth,Size);
    FVertical.SetBounds(ViewWidth,0,Size,ViewHeight);
    var Duration := Max(0.001,JN(FTimeline,'duration'));
    FHorizontal.PageSize := 0;
    FHorizontal.SetParams(Round(FOffset/Duration*1000000),0,1000000);
    FHorizontal.PageSize := EnsureRange(Round(VisibleSpan/Duration*1000000),1,1000000);
    FHorizontal.LargeChange := EnsureRange(FHorizontal.PageSize div 2,1,32767);
    FHorizontal.SmallChange := EnsureRange(FHorizontal.PageSize div 10,1,32767);
    FHorizontal.Enabled := VisibleSpan<Duration;
    var Page := Max(1,ViewHeight-RulerHeight);
    var Content := RowHeightPixels*TrackCount;
    FVertical.PageSize := 0;
    FVertical.SetParams(EnsureRange(FVertical.Position,0,Max(0,Content-Page)),0,Max(Content,Page));
    FVertical.PageSize := Min(Page,FVertical.Max);
    FVertical.SmallChange := UiScale(20); FVertical.LargeChange := Max(1,Page div 2);
    FVertical.Enabled := Content>Page;
  finally FUpdatingScroll := False; end;
end;
procedure TRigmMovieTimeline.Resize;
begin
  inherited;
  if FLayoutDragging then begin
    if (FHorizontal<>nil) and (FVertical<>nil) then begin
      FHorizontal.SetBounds(0,ViewHeight,ViewWidth,UiScale(17));
      FVertical.SetBounds(ViewWidth,0,UiScale(17),ViewHeight);
    end;
    FCacheDirty := True; Exit;
  end;
  UpdateScrollBars; FCacheDirty := True; Invalidate;
end;
procedure TRigmMovieTimeline.SetLayoutDragging(Value: Boolean);
begin
  if FLayoutDragging=Value then Exit;
  FLayoutDragging := Value;
  if not Value then begin UpdateScrollBars; FCacheDirty := True; Invalidate; end;
end;
procedure TRigmMovieTimeline.ScrollChanged(Sender: TObject);
begin
  if FUpdatingScroll then Exit;
  if Sender=FHorizontal then PanTo(FHorizontal.Position/1000000.0*JN(FTimeline,'duration'))
  else begin FCacheDirty := True; FContentDirty := True; Invalidate; end;
end;
procedure TRigmMovieTimeline.PanTo(Offset: Double);
begin
  FOffset := EnsureRange(Offset,0.0,Max(0.0,JN(FTimeline,'duration')-VisibleSpan));
  UpdateScrollBars; FCacheDirty := True; FContentDirty := True; Invalidate;
end;
procedure TRigmMovieTimeline.ResetView;
begin FSpan := 0; FOffset := 0; FVertical.Position := 0; UpdateScrollBars; FCacheDirty := True; FContentDirty := True; Invalidate; end;
procedure TRigmMovieTimeline.WheelAt(Delta: Integer; const Position: TPoint);
begin
  Inc(FWheelRemainder,Delta); var Steps := FWheelRemainder div 120; FWheelRemainder := FWheelRemainder mod 120;
  if Steps=0 then Exit;
  if Position.X>=ViewWidth then begin
    FVertical.Position := EnsureRange(FVertical.Position-Steps*UiScale(20),0,Max(0,FVertical.Max-FVertical.PageSize)); Exit;
  end;
  if Position.Y>=ViewHeight then begin PanTo(FOffset-Steps*VisibleSpan*0.12); Exit; end;
  if Position.Y<RulerHeight then begin PanTo(FOffset-Steps*VisibleSpan*0.12); Exit; end;
  var Duration := Max(0.001,JN(FTimeline,'duration')); var Ratio := EnsureRange((Position.X-HeaderWidth)/Max(1,ViewWidth-HeaderWidth),0.0,1.0);
  var Anchor := FOffset+VisibleSpan*Ratio;
  var Minimum := Min(Duration,Max(0.001,4/Max(1,JN(FTimeline,'fps',30))));
  FSpan := EnsureRange(VisibleSpan*Power(1.25,-EnsureRange(Steps,-12,12)),Minimum,Duration);
  PanTo(Anchor-FSpan*Ratio);
end;
function TRigmMovieTimeline.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin Result := PtInRect(ClientRect,ScreenToClient(MousePos)); if Result then WheelAt(WheelDelta,ScreenToClient(MousePos)); end;
function TRigmMovieTimeline.PlayheadX: Integer;
begin
  Result := HeaderWidth+Round((FTime-FOffset)/VisibleSpan*Max(1,ViewWidth-HeaderWidth));
end;
procedure TRigmMovieTimeline.SetTime(Seconds: Double);
begin
  Seconds := EnsureRange(Seconds,0.0,JN(FTimeline,'duration'));
  if SameValue(FTime,Seconds,0.000001) then Exit;
  var OldX := PlayheadX; FTime := Seconds;
  if (FSpan>0) and ((FTime<FOffset) or (FTime>FOffset+FSpan)) then begin
    PanTo(FTime-VisibleSpan/2);
  end else if HandleAllocated then begin
    var R := Rect(OldX-2,0,OldX+3,Height); InvalidateRect(Handle,@R,False);
    R := Rect(PlayheadX-2,0,PlayheadX+3,Height); InvalidateRect(Handle,@R,False);
  end else Invalidate;
end;
procedure TRigmMovieTimeline.SetSpan(Seconds: Double);
begin FSpan := Max(0,Seconds); if FSpan<=0 then PanTo(0) else PanTo(FTime-VisibleSpan/2); end;
function TRigmMovieTimeline.SecondsAt(X: Integer): Double;
begin
  Result := SnapTime(FOffset+EnsureRange((X-HeaderWidth)/Max(1,ViewWidth-HeaderWidth),0.0,1.0)*VisibleSpan);
end;
procedure TRigmMovieTimeline.SelectCue(const CueId: string);
begin
  if FSelectedCueId=CueId then Exit;
  FSelectedCueId := CueId; FCacheDirty := True; FContentDirty := True; Invalidate;
end;
procedure TRigmMovieTimeline.MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if (Button=mbLeft) and (X>=HeaderWidth) and (X<ViewWidth) and (Y<ViewHeight) then begin
    MouseCapture := True; SetTime(SecondsAt(X));
    if (Y>=RulerHeight) and (FTimeline.GetValue('cues')<>nil) then
      for var V in JA(FTimeline,'cues') do begin
        var C := TJSONObject(V);
        if (FTime>=JN(C,'start')) and (FTime<JN(C,'start')+JN(C,'duration')) then begin
          SelectCue(JS(C,'id')); if Assigned(FOnSelectCue) then FOnSelectCue(Self); Break;
        end;
      end;
    Invalidate; if Assigned(FOnSeek) then FOnSeek(Self);
  end;
end;
procedure TRigmMovieTimeline.DrawTracks(Target: TCanvas);
const TrackNames: array[0..3] of string = ('映像','キャラ','音声','字幕');
var Span,Duration: Double; Left,Right,X,Center,Header,RowHeight: Integer;
    CurrentCue: TJSONObject;
  function Position(Time: Double): Integer;
  begin Result := Header+Round((Time-FOffset)/Span*Max(1,ViewWidth-Header)); end;
  procedure Clip(Track: Integer; Color: TColor; const Text: string; Finish: Integer);
  begin
    var R := Rect(Left+1,RulerHeight+Track*RowHeight+2-FVertical.Position,Max(Left+1,Finish-1),RulerHeight+(Track+1)*RowHeight-2-FVertical.Position);
    var TextLeft := R.Left+UiScale(6);
    Target.Brush.Color := Color; Target.FillRect(R);
    if JS(CurrentCue,'id')=FSelectedCueId then begin Target.Brush.Style := bsClear; Target.Pen.Color := $EED0A0; Target.Rectangle(R); Target.Brush.Style := bsSolid; end;
    if (Track=0) and FileExists(JS(CurrentCue,'image')) and (R.Width>UiScale(8)) then begin
      var Picture := TPicture.Create;
      try
        try
          Picture.LoadFromFile(JS(CurrentCue,'image'));
          if (Picture.Width>0) and (Picture.Height>0) then begin
            var Ratio := Min((R.Width-UiScale(4))/Picture.Width,(R.Height-UiScale(4))/Picture.Height);
            var W := Max(1,Round(Picture.Width*Ratio)); var H := Max(1,Round(Picture.Height*Ratio));
            Target.StretchDraw(Rect(R.Left+UiScale(2),R.Top+(R.Height-H) div 2,R.Left+UiScale(2)+W,R.Top+(R.Height-H) div 2+H),Picture.Graphic);
            TextLeft := R.Left+UiScale(8)+W;
            Inc(FThumbnailCount);
          end;
        except // A broken thumbnail must not disable timeline selection.
        end;
      finally Picture.Free; end;
    end;
    var LabelRect := Rect(TextLeft,R.Top+UiScale(2),R.Right-UiScale(5),R.Bottom-UiScale(2));
    if Track=2 then LabelRect.Bottom := Min(LabelRect.Bottom,LabelRect.Top+FTextHeight);
    if (Text<>'') and (LabelRect.Width>=UiScale(20)) and (LabelRect.Height>=FTextHeight) then begin
      Target.Brush.Style := bsClear;
      DrawText(Target.Handle,PChar(Text),Length(Text),LabelRect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
      Target.Brush.Style := bsSolid; Inc(FLabelCount);
    end;
  end;
begin
  Inc(FStaticBuildCount); FLabelCount := 0;
  Target.Brush.Color := $202020; Target.FillRect(ClientRect); Target.Font.Assign(Font);
  Target.Font.Color := clWhite; Target.Font.Height := -UiScale(16);
  FTextHeight := Target.TextHeight('Mg日本語');
  Header := HeaderWidth; RowHeight := RowHeightPixels;
  Duration := JN(FTimeline,'duration'); Span := VisibleSpan;
  var Step := 1.0; if Span>15 then Step := 5; if Span>60 then Step := 10; if Span>180 then Step := 30;
  while Step/Span*Max(1,ViewWidth-Header)<Target.TextWidth(FormatFloat('0',FOffset+Span)+'s')+UiScale(12) do Step := Step*2;
  var Mark := Ceil(FOffset/Step)*Step;
  while Mark<=FOffset+Span do begin
    X := Position(Mark); Target.Pen.Color := $404040; Target.MoveTo(X,RulerHeight-UiScale(6)); Target.LineTo(X,ViewHeight);
    var TickRect := Rect(X+UiScale(3),0,Min(ViewWidth,X+Round(Step/Span*Max(1,ViewWidth-Header))-UiScale(3)),RulerHeight-UiScale(6));
    var TickText := FormatFloat('0.#',Mark)+'s';
    Target.Brush.Style := bsClear; DrawText(Target.Handle,PChar(TickText),Length(TickText),TickRect,DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX); Target.Brush.Style := bsSolid;
    Mark := Mark+Step;
  end;
  var Saved := SaveDC(Target.Handle);
  IntersectClipRect(Target.Handle,Header,RulerHeight,ViewWidth,ViewHeight);
  if FTimeline.GetValue('cues')<>nil then for var V in JA(FTimeline,'cues') do begin
    CurrentCue := TJSONObject(V); var Start := JN(CurrentCue,'start'); var Finish := Start+JN(CurrentCue,'duration');
    if (Finish<FOffset) or (Start>FOffset+Span) then Continue;
    Left := Max(Header,Position(Start)); Right := Min(ViewWidth,Position(Finish));
    Clip(0,$645038,JS(CurrentCue,'sceneTitle',JS(CurrentCue,'scene'))+' / '+JS(CurrentCue,'imageName','画像'),Right);
    Clip(1,$745848,JS(CurrentCue,'characterName',JS(CurrentCue,'speaker'))+' / '+JS(CurrentCue,'motionLabel',JS(CurrentCue,'motion')),Right);
    if JB(CurrentCue,'audioReady') then Clip(2,$605838,JS(CurrentCue,'speakerName',JS(CurrentCue,'speaker'))+' / '+JS(CurrentCue,'text'),Min(Right,Position(Start+JN(CurrentCue,'audioSeconds'))))
    else Clip(2,$404050,'音声未更新 / '+JS(CurrentCue,'text'),Right);
    Clip(3,$665040,JS(CurrentCue,'subtitle'),Right);
  end;
  if FTimeline.GetValue('endCards') is TJSONArray then for var V in JA(FTimeline,'endCards') do begin
    CurrentCue := TJSONObject(V); var Start := JN(CurrentCue,'start'); var Finish := Start+JN(CurrentCue,'duration'); if (Finish<FOffset) or (Start>FOffset+Span) then Continue;
    Left := Max(Header,Position(Start)); Right := Min(ViewWidth,Position(Finish)); var Caption := '終了画像'; if JS(CurrentCue,'kind')='thumbnail' then Caption := 'サムネイル'; Clip(0,$645038,Caption,Right); Clip(2,$404040,'無音',Right);
  end;
  var WaveTop := RulerHeight+RowHeight*2+FTextHeight+UiScale(6)-FVertical.Position;
  var WaveBottom := RulerHeight+RowHeight*3-UiScale(3)-FVertical.Position;
  Center := (WaveTop+WaveBottom) div 2;
  var WaveHeight := Max(1,(WaveBottom-WaveTop) div 2);
  if (FWaveform.GetValue('peaks')<>nil) and JB(FWaveform,'current') then begin
    var Peaks := JA(FWaveform,'peaks'); var Amplitude := Max(1,JN(FWaveform,'amplitudeScale',32768));
    Target.Pen.Color := $E0CA70;
    for X := Header to ViewWidth-1 do begin
      var Seconds := FOffset+(X-Header)/Max(1,ViewWidth-Header)*Span;
      var Index := Floor(Seconds/Max(0.001,JN(FWaveform,'duration'))*Peaks.Count);
      if (Index<0) or (Index>=Peaks.Count) then Continue;
      var Pair := TJSONArray(Peaks[Index]);
      Target.MoveTo(X,Center-Round(TJSONNumber(Pair[1]).AsDouble/Amplitude*WaveHeight));
      Target.LineTo(X,Center-Round(TJSONNumber(Pair[0]).AsDouble/Amplitude*WaveHeight)+1);
    end;
  end;
  RestoreDC(Target.Handle,Saved);
  Target.Brush.Color := $282828; Target.FillRect(Rect(0,0,Header,ViewHeight));
  Target.Brush.Style := bsClear;
  var HeaderRect := Rect(UiScale(10),0,Header-UiScale(8),RulerHeight);
  DrawText(Target.Handle,'時間',2,HeaderRect,DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Saved := SaveDC(Target.Handle); IntersectClipRect(Target.Handle,0,RulerHeight,ViewWidth,ViewHeight);
  for var I := 0 to TrackCount-1 do begin
    HeaderRect := Rect(UiScale(10),RulerHeight+I*RowHeight-FVertical.Position,Header-UiScale(8),RulerHeight+(I+1)*RowHeight-FVertical.Position);
    var Name := 'トラック '+IntToStr(I+1); if I<4 then Name := TrackNames[I];
    if (FTimeline.GetValue('tracks') is TJSONArray) and (I<JA(FTimeline,'tracks').Count) then
      Name := JS(TJSONObject(JA(FTimeline,'tracks')[I]),'name',Name);
    DrawText(Target.Handle,PChar(Name),Length(Name),HeaderRect,DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    Target.Pen.Color := $606060; Target.MoveTo(0,RulerHeight+(I+1)*RowHeight-FVertical.Position); Target.LineTo(ViewWidth,RulerHeight+(I+1)*RowHeight-FVertical.Position);
  end;
  RestoreDC(Target.Handle,Saved); Target.Brush.Style := bsSolid;

end;
procedure TRigmMovieTimeline.Paint;
begin
  Inc(FPaintCount);
  if FContentDirty or (not FLayoutDragging and (FCacheDirty or (FCache.Width<>Width) or (FCache.Height<>Height) or
    (FCachePPI<>UiScale(96)) or (FCacheFont<>Font.Height))) then begin
    FCache.SetSize(Max(1,Width),Max(1,Height)); DrawTracks(FCache.Canvas);
    FCachePPI := UiScale(96); FCacheFont := Font.Height; FCacheDirty := False; FContentDirty := False;
  end;
  Canvas.Brush.Color := $202020; Canvas.FillRect(ClientRect);
  Canvas.Draw(0,0,FCache); Canvas.Pen.Color := clRed;
  if (PlayheadX>=HeaderWidth) and (PlayheadX<ViewWidth) then begin Canvas.MoveTo(PlayheadX,0); Canvas.LineTo(PlayheadX,ViewHeight); end;
end;
procedure TRigmMovieTimeline.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  inherited;
  if not MouseCapture and (X>=HeaderWidth) and (Y>=RulerHeight) and (FTimeline.GetValue('cues')<>nil) then begin
    var Time := SecondsAt(X);
    for var V in JA(FTimeline,'cues') do begin
      var C := TJSONObject(V);
      if (Time>=JN(C,'start')) and (Time<JN(C,'start')+JN(C,'duration')) then begin
        Hint := JS(C,'sceneTitle',JS(C,'scene'))+' / '+JS(C,'imageName')+sLineBreak+
          JS(C,'characterName')+' / '+JS(C,'motionLabel')+' / '+JS(C,'speakerName',JS(C,'speaker'))+sLineBreak+
          FormatFloat('0.00',JN(C,'start'))+' - '+FormatFloat('0.00',JN(C,'start')+JN(C,'duration'))+' s'+sLineBreak+JS(C,'subtitle');
        Break;
      end;
    end;
  end;
  if MouseCapture and (ssLeft in Shift) then begin SetTime(SecondsAt(X)); if Assigned(FOnSeek) then FOnSeek(Self); end;
end;
procedure TRigmMovieTimeline.MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
begin inherited; if Button=mbLeft then MouseCapture := False; end;
end.
