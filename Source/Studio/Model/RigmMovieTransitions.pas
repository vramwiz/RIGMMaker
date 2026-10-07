// Scene image transitions share the preview and export renderer.
unit RigmMovieTransitions;

interface
uses System.JSON;
procedure ValidateMovieImageTransitions(Animation: TJSONObject);
procedure MovieImageTransitionTimes(Animation: TJSONObject; Duration: Double; out Enter,Leave: Double);
function MovieImageOpacity(Animation: TJSONObject; Local,Duration: Double): Double;

implementation
uses System.SysUtils, System.Math, System.StrUtils, RigmJson, RigmModel;

procedure ValidateMovieImageTransitions(Animation: TJSONObject);
begin
  for var Key in ['enter','exit'] do begin
    if (Animation.GetValue(Key)<>nil) and not (Animation.GetValue(Key) is TJSONString) then raise ERigm.Create('Image animation type must be a string');
    if not MatchStr(JS(Animation,Key,'none'),['none','fade']) then raise ERigm.Create('Image animation supports none or fade');
  end;
  for var Key in ['enterSeconds','exitSeconds'] do begin
    if (Animation.GetValue(Key)<>nil) and not (Animation.GetValue(Key) is TJSONNumber) then raise ERigm.Create('Image animation duration must be numeric');
    var Seconds := JN(Animation,Key,0.5);
    if not Finite(Seconds) or (Seconds<0) or (Seconds>60) then raise ERigm.Create('Image animation duration must be 0..60 seconds');
  end;
end;

procedure MovieImageTransitionTimes(Animation: TJSONObject; Duration: Double; out Enter,Leave: Double);
begin
  Enter := 0; Leave := 0;
  if JS(Animation,'enter','none')='fade' then Enter := JN(Animation,'enterSeconds',0.5);
  if JS(Animation,'exit','none')='fade' then Leave := JN(Animation,'exitSeconds',0.5);
  Duration := Max(0.0,Duration);
  // Proportionally shorten both transitions; they never overlap in a short scene.
  if (Enter+Leave>Duration) and (Enter+Leave>0) then begin
    var Scale := Duration/(Enter+Leave); Enter := Enter*Scale; Leave := Leave*Scale;
  end;
end;

function MovieImageOpacity(Animation: TJSONObject; Local,Duration: Double): Double;
begin
  var Enter,Leave: Double; MovieImageTransitionTimes(Animation,Duration,Enter,Leave);
  Result := 1;
  if Enter>0 then Result := Min(Result,EnsureRange(Local/Enter,0.0,1.0));
  if Leave>0 then Result := Min(Result,EnsureRange((Duration-Local)/Leave,0.0,1.0));
end;
end.
