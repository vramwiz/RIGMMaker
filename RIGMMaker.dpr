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
  var ResultPath := ''; var SmokePath := ''; var UiCheck := False; var CreateCheck := False;
  for var Index := 1 to ParamCount-1 do begin
    if ParamStr(Index)='--verify-wizard' then ResultPath := ParamStr(Index+1);
    if ParamStr(Index)='--smoke' then SmokePath := ParamStr(Index+1);
    if ParamStr(Index)='--verify-ui-responsiveness' then begin ResultPath := ParamStr(Index+1); UiCheck := True; end;
    if ParamStr(Index)='--verify-character-create' then begin ResultPath := ParamStr(Index+1); CreateCheck := True; end;
  end;
  if ResultPath<>'' then begin
    try
      try if CreateCheck then VerifyCharacterCreate(RigmWizardMain,ResultPath)
      else if UiCheck then VerifyUiResponsiveness(RigmWizardMain,ResultPath) else VerifyWizard(RigmWizardMain,ResultPath,SmokePath);
      except on E: Exception do begin TFile.WriteAllText(ResultPath+'.error.txt',E.ClassName+': '+E.Message,TEncoding.UTF8); ExitCode := 1; end; end;
    finally RigmWizardMain.Free; end;
  end else Application.Run;
end.
