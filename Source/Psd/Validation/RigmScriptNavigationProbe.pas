unit RigmScriptNavigationProbe;
// 既存の工程別検証も、実際の工程リストを選んで移動する。
interface
uses System.Classes, RigmWizardWorkspace;
type
  TRigmScriptStageProbe = class(TComponent)
  private
    FFrame: TComponent; FWorkspace: TRigmWizardWorkspace;
    function GetEnabled: Boolean;
    function GetVisible: Boolean;
  public
    constructor CreateForFrame(Frame: TComponent; Workspace: TRigmWizardWorkspace);
    procedure Click;
    property Enabled: Boolean read GetEnabled;
    property Visible: Boolean read GetVisible;
  end;
procedure ClickScriptStage(Frame: TComponent; const Stage: string);
implementation
uses System.SysUtils, Vcl.StdCtrls, RigmJson, RigmScriptNavigationModel, RigmScriptPlacementModel;
procedure ClickScriptStage(Frame: TComponent; const Stage: string);
begin
  var List := Frame.FindComponent('ScriptStages') as TListBox;
  if List.CanFocus then List.SetFocus;
  var Index := List.Items.IndexOf(ScriptStageCaption(Stage));
  if Index<0 then Exit;
  List.ItemIndex := Index; List.OnClick(List);
end;
constructor TRigmScriptStageProbe.CreateForFrame(Frame: TComponent; Workspace: TRigmWizardWorkspace);
begin inherited Create(Frame); FFrame := Frame; FWorkspace := Workspace; end;
function TRigmScriptStageProbe.GetEnabled: Boolean;
begin
  var State := FWorkspace.ScriptStatus;
  try Result := ScriptCanAdvance(State); finally State.Free; end;
end;
function TRigmScriptStageProbe.GetVisible: Boolean;
begin
  var State := FWorkspace.ScriptStatus;
  try
    if not JB(State,'hasProject') then Exit(False);
    var Next := ScriptNextStage(FWorkspace.CurrentScriptStage,JO(State,'wizard'));
    var List := FFrame.FindComponent('ScriptStages') as TListBox;
    Result := List.Items.IndexOf(ScriptStageCaption(Next))>=0;
  finally State.Free; end;
end;
procedure TRigmScriptStageProbe.Click;
begin
  var State := FWorkspace.ScriptStatus;
  try if JB(State,'hasProject') then ClickScriptStage(FFrame,ScriptNextStage(FWorkspace.CurrentScriptStage,JO(State,'wizard')));
  finally State.Free; end;
end;
end.
