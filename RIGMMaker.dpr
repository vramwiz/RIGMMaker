program RIGMMaker;

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  RigmWizardMainForm in 'Source\Shell\RigmWizardMainForm.pas',
  RigmWizardValidation in 'Source\Psd\Validation\RigmWizardValidation.pas';

{$R *.res}

begin
  Application.Initialize;
  TStyleManager.TrySetStyle('Windows Modern Dark');
  Application.MainFormOnTaskbar := True;
  Application.Title := 'RIGM Maker';
  Application.CreateForm(TRigmWizardMainForm, RigmWizardMain);
  var ResultPath := ''; var SmokePath := ''; var UiCheck := False; var CreateCheck := False; var ScriptCheck := False; var ScriptReopen := False; var CharactersCheck := False;
  var SubtitleCheck := False; var CastingCheck := False; var ReviewCheck := False; var ThumbnailCheck := False; var LayoutCheck := False; var PlacementCheck := False; var TextCheck := False;
  for var Index := 1 to ParamCount-1 do begin
    if ParamStr(Index)='--verify-wizard' then ResultPath := ParamStr(Index+1);
    if ParamStr(Index)='--smoke' then SmokePath := ParamStr(Index+1);
    if ParamStr(Index)='--verify-ui-responsiveness' then begin ResultPath := ParamStr(Index+1); UiCheck := True; end;
    if ParamStr(Index)='--verify-character-create' then begin ResultPath := ParamStr(Index+1); CreateCheck := True; end;
    if ParamStr(Index)='--verify-script-title' then begin ResultPath := ParamStr(Index+1); ScriptCheck := True; end;
    if ParamStr(Index)='--verify-script-title-reopen' then begin ResultPath := ParamStr(Index+1); ScriptCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-characters' then begin ResultPath := ParamStr(Index+1); CharactersCheck := True; end;
    if ParamStr(Index)='--verify-script-characters-reopen' then begin ResultPath := ParamStr(Index+1); CharactersCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-thumbnail-cache' then begin ResultPath := ParamStr(Index+1); ThumbnailCheck := True; end;
    if ParamStr(Index)='--verify-thumbnail-cache-reopen' then begin ResultPath := ParamStr(Index+1); ThumbnailCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-layout' then begin ResultPath := ParamStr(Index+1); LayoutCheck := True; end;
    if ParamStr(Index)='--verify-script-layout-reopen' then begin ResultPath := ParamStr(Index+1); LayoutCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-placement' then begin ResultPath := ParamStr(Index+1); PlacementCheck := True; end;
    if ParamStr(Index)='--verify-script-placement-reopen' then begin ResultPath := ParamStr(Index+1); PlacementCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-subtitles' then begin ResultPath := ParamStr(Index+1); SubtitleCheck := True; end;
    if ParamStr(Index)='--verify-script-subtitles-reopen' then begin ResultPath := ParamStr(Index+1); SubtitleCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-casting' then begin ResultPath := ParamStr(Index+1); CastingCheck := True; end;
    if ParamStr(Index)='--verify-script-casting-reopen' then begin ResultPath := ParamStr(Index+1); CastingCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-review' then begin ResultPath := ParamStr(Index+1); ReviewCheck := True; end;
    if ParamStr(Index)='--verify-script-review-reopen' then begin ResultPath := ParamStr(Index+1); ReviewCheck := True; ScriptReopen := True; end;
    if ParamStr(Index)='--verify-script-text' then begin ResultPath := ParamStr(Index+1); TextCheck := True; end;
    if ParamStr(Index)='--verify-script-text-reopen' then begin ResultPath := ParamStr(Index+1); TextCheck := True; ScriptReopen := True; end;
  end;
  if ResultPath<>'' then begin
    try
      try if SubtitleCheck then VerifyScriptSubtitles(RigmWizardMain,ResultPath,ScriptReopen)
      else if CastingCheck then VerifyScriptCasting(RigmWizardMain,ResultPath,ScriptReopen)
      else if ReviewCheck then VerifyScriptReview(RigmWizardMain,ResultPath,ScriptReopen)
      else if TextCheck then VerifyScriptText(RigmWizardMain,ResultPath,ScriptReopen)
      else if PlacementCheck then VerifyScriptPlacement(RigmWizardMain,ResultPath,ScriptReopen)
      else if LayoutCheck then VerifyScriptLayout(RigmWizardMain,ResultPath,ScriptReopen)
      else if ThumbnailCheck then VerifyThumbnailCache(RigmWizardMain,ResultPath,ScriptReopen)
      else if CharactersCheck then VerifyScriptCharacters(RigmWizardMain,ResultPath,ScriptReopen)
      else if ScriptCheck then VerifyScriptTitle(RigmWizardMain,ResultPath,ScriptReopen)
      else if CreateCheck then VerifyCharacterCreate(RigmWizardMain,ResultPath)
      else if UiCheck then VerifyUiResponsiveness(RigmWizardMain,ResultPath) else VerifyWizard(RigmWizardMain,ResultPath,SmokePath);
      except on E: Exception do begin TFile.WriteAllText(ResultPath+'.error.txt',E.ClassName+': '+E.Message,TEncoding.UTF8); ExitCode := 1; end; end;
    finally RigmWizardMain.Free; end;
  end else Application.Run;
end.
