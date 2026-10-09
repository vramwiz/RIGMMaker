program RIGMWizard;

// 単一メインフォームの中間成果。通常版の入口・EXEを置き換えない隔離検証用。
uses System.SysUtils, System.IOUtils, System.Classes, Vcl.Forms,
  RigmWizardMainForm in 'Source\Shell\RigmWizardMainForm.pas',
  RigmScriptResearchModel in 'Source\Studio\Model\RigmScriptResearchModel.pas',
  RigmScriptNavigationProbe in 'Source\Psd\Validation\RigmScriptNavigationProbe.pas',
  RigmWizardValidation in 'Source\Psd\Validation\RigmWizardValidation.pas';
begin
  Application.Initialize; Application.MainFormOnTaskbar := True; Application.Title := 'RIGM Maker';
  Application.CreateForm(TRigmWizardMainForm,RigmWizardMain);
  var ResultPath := ''; var SmokePath := '';
  for var Index := 1 to ParamCount-1 do begin
    if ParamStr(Index)='--verify-wizard' then ResultPath := ParamStr(Index+1);
    if ParamStr(Index)='--smoke' then SmokePath := ParamStr(Index+1);
  end;
  if ResultPath<>'' then begin
    try
      try VerifyWizard(RigmWizardMain,ResultPath,SmokePath);
      except on E: Exception do begin TFile.WriteAllText(ResultPath+'.error.txt',E.ClassName+': '+E.Message,TEncoding.UTF8); ExitCode := 1; end; end;
    finally RigmWizardMain.Free; end; // 単一所有者が生成済みのページを一度だけ解放する。
  end else Application.Run;
end.
