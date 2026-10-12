procedure CheckPlacementOverflow;
begin
  var Frame := StageFrame(TRigmScriptPlacementFrame) as TRigmScriptPlacementFrame;
  var Path := JS(TJSONObject(JA(W.ScriptDraft.ScriptWizard,'selectedCharacters')[0]),'path');
  var Initial := Placement(W.ScriptDraft,Path).Clone as TJSONObject;
  try
    var Area := RectF(0,0,1920,1080); var Original := RectF(100,100,500,800);
    var Moved := DragPlacement(Original,Area,-1,-800,-700,True,False);
    Check((Moved.Left<0) and (Moved.Top<0) and (Moved.Width=Original.Width),'dragging allows negative coordinates without shrinking the character');
    var Bigger := DragPlacement(Original,Area,4,1900,900,True,False);
    Check((Bigger.Right>1920) and (Bigger.Bottom>1080) and (Abs(Bigger.Width/Bigger.Height-Original.Width/Original.Height)<0.001),
      'resizing can exceed the canvas while retaining the aspect ratio');
    var Box := Frame.Preview.CharacterBounds(Path); var Point := Box.CenterPoint;
    Frame.Preview.Perform(WM_LBUTTONDOWN,MK_LBUTTON,MakeLParam(Point.X,Point.Y));
    Check(Frame.Preview.Dragging,'native placement preview begins a captured drag');
    var Target := MakeLParam((Point.X-Frame.Preview.Width) and $FFFF,(Point.Y-Frame.Preview.Height) and $FFFF);
    Frame.Preview.Perform(WM_MOUSEMOVE,MK_LBUTTON,Target);
    Frame.Preview.Perform(WM_LBUTTONUP,0,Target);
    Check(not Frame.Preview.Dragging and (JN(Placement(W.ScriptDraft,Path),'x')<0),'native mouse drag commits the off-screen character');
    var A := TJSONObject.Create;
    try
      A.AddPair('projectId',W.ScriptDraft.Id); AddN(A,'revision',W.ScriptDraft.Revision); A.AddPair('path',Path);
      AddN(A,'x',1.4); AddN(A,'y',-0.4); AddN(A,'width',1.1); AddN(A,'height',0.8); AddB(A,'flipX',True);
      var Reply := W.Command('app-script-set-placement',A); Reply.Free;
    finally A.Free; end;
    Check((JN(Placement(W.ScriptDraft,Path),'x')=1.4) and JB(Placement(W.ScriptDraft,Path),'flipX'),
      'shared pipe command accepts a wholly off-screen placement');
    var P := W.ScriptDraft.Clone;
    try
      P.Layout := 'l'; P.LDirection := 'right'; PreparePlacements(P,W.Thumbnails);
      Check(JN(Placement(P,Path),'x')=1.4,'L-shaped layout preserves an existing off-screen placement');
      P.EnableComposition; P.Validate;
      Check((P.Characters.Count>0) and (P.Characters[0].X>1920),'movie model accepts the same linked off-screen placement');
    finally P.Free; end;
    W.SaveScriptDraft(False); W.OpenScriptDraft(W.ScriptDraft.FileName);
    Check((JN(Placement(W.ScriptDraft,Path),'x')=1.4) and (JN(Placement(W.ScriptDraft,Path),'y')=-0.4),
      'save and reopen preserve the off-screen position and size');
    Frame := StageFrame(TRigmScriptPlacementFrame) as TRigmScriptPlacementFrame; Frame.RefreshState;
    var Reset := Frame.FindComponent('ScriptPlacementReset') as TButton;
    Check(Reset.Visible and Reset.Enabled,'reset stays available through the character list even when its sprite is outside the preview');
    Reset.Click;
    for var Key in ['x','y','width','height'] do Check(Abs(JN(Placement(W.ScriptDraft,Path),Key)-JN(Initial,Key))<0.000001,'reset restores initial '+Key);
    Check(JB(Placement(W.ScriptDraft,Path),'flipX'),'reset retains the selected character and mirror setting');
    Capture('placement-reset');
  finally Initial.Free; end;
end;
