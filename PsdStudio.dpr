program PsdStudio;

// PSD系統の独立入口。RIGMMaker.dprと既存メインフォームには接続しない。
uses System.SysUtils, Winapi.Windows, Vcl.Forms, PsdStudioForm in 'Source\Psd\Shell\PsdStudioForm.pas';
begin
  Application.Initialize; Application.MainFormOnTaskbar := True;
  Application.Title := 'PSD立ち絵スタジオ';
  Application.CreateForm(TPsdStudioForm, PsdStudioWindow);
  var Smoke := '';
  var GuiCheck := '';
  var PageCheck := '';
  var SmokeMs := 6000;
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--smoke' then Smoke := ParamStr(Index + 1);
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--verify-gui' then GuiCheck := ParamStr(Index + 1);
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--verify-pages' then PageCheck := ParamStr(Index + 1);
  for var Index := 1 to ParamCount - 1 do if ParamStr(Index) = '--smoke-ms' then begin
    SmokeMs := StrToInt(ParamStr(Index + 1)); if (SmokeMs < 1000) or (SmokeMs > 60000) then raise Exception.Create('Smoke duration limit');
  end;
  if Smoke <> '' then begin
    if GuiCheck <> '' then PsdStudioWindow.VerifyGuiFlow(GuiCheck);
    if PageCheck <> '' then PsdStudioWindow.VerifyPageFlow(PageCheck);
    PsdStudioWindow.CaptureSmoke(Smoke);
    // 実パイプ検証中もVCLの要求通知を処理し、検証終了後は自分で正常終了。
    var Deadline := GetTickCount64 + UInt64(SmokeMs);
    while GetTickCount64 < Deadline do begin Application.ProcessMessages; Sleep(10); end;
    PsdStudioWindow.Free;
  end
  else Application.Run;
end.
