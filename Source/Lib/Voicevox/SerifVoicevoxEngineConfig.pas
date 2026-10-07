// Syncroh2のEXE選択規則を採用。RIGMMaker.exeの隣へだけ設定を保存する。
unit SerifVoicevoxEngineConfig;
interface
type
  TSerifVoicevoxEngineConfig = class
  private
    FFileName,FLastError,FLoadedHash: string;
    function CurrentHash: string;
  public
    constructor Create;
    class function NormalizeEngineSelection(const FileName: string; out EngineExe: string): Boolean; static;
    function Resolve(out EngineExe: string): Boolean;
    function Save(const EngineExe: string): Boolean;
    property FileName: string read FFileName;
    property LastError: string read FLastError;
  end;
implementation
uses System.Classes, System.IniFiles, System.IOUtils, System.SysUtils,
  System.Hash, System.SyncObjs, Winapi.Windows;
constructor TSerifVoicevoxEngineConfig.Create;
begin inherited; FFileName := TPath.Combine(ExtractFilePath(ParamStr(0)),'VoicevoxEngine.ini'); end;
function TSerifVoicevoxEngineConfig.CurrentHash: string;
begin Result := ''; if FileExists(FFileName) then Result := THashSHA2.GetHashStringFromFile(FFileName); end;
class function TSerifVoicevoxEngineConfig.NormalizeEngineSelection(const FileName: string; out EngineExe: string): Boolean;
begin
  Result := False; EngineExe := '';
  if Trim(FileName)='' then Exit;
  try
    var Candidate := TPath.GetFullPath(Trim(FileName));
    if SameText(ExtractFileName(Candidate),'VOICEVOX.exe') then Candidate := TPath.Combine(ExtractFilePath(Candidate),'vv-engine\run.exe');
    if not SameText(ExtractFileName(Candidate),'run.exe') or not FileExists(Candidate) then Exit;
    EngineExe := Candidate; Result := True;
  except EngineExe := ''; end;
end;
function TSerifVoicevoxEngineConfig.Resolve(out EngineExe: string): Boolean;
begin
  Result := False; EngineExe := ''; FLastError := '';
  try
    FLoadedHash := CurrentHash;
    var Ini := TMemIniFile.Create(FFileName,TEncoding.UTF8);
    try
      var Saved := Ini.ReadString('VOICEVOX','EngineExe','');
      if CurrentHash<>FLoadedHash then raise Exception.Create('VOICEVOX設定が読込中に変わりました。再選択してください。');
      if NormalizeEngineSelection(Saved,EngineExe) then Exit(True);
      if Saved<>'' then FLastError := '保存したVOICEVOX Engineが見つかりません。EXEを選び直してください。';
    finally Ini.Free; end;
    var Local := GetEnvironmentVariable('LOCALAPPDATA');
    if Local<>'' then Result := NormalizeEngineSelection(TPath.Combine(Local,'Programs\VOICEVOX\VOICEVOX.exe'),EngineExe);
  except on E: Exception do FLastError := E.Message; end;
end;
function TSerifVoicevoxEngineConfig.Save(const EngineExe: string): Boolean;
var Normalized,Temporary: string;
begin
  Result := False; FLastError := ''; Temporary := '';
  if not NormalizeEngineSelection(EngineExe,Normalized) then begin FLastError := 'VOICEVOX.exeまたはvv-engine\run.exeを選択してください。'; Exit; end;
  var Lock := TMutex.Create(nil,False,'Local\RIGMMaker.VoicevoxConfig.'+THashSHA2.GetHashString(LowerCase(FFileName)));
  try
    try
      if Lock.WaitFor(1000)<>wrSignaled then raise Exception.Create('他の操作がVOICEVOX設定を保存中です。');
      try
        if CurrentHash<>FLoadedHash then raise Exception.Create('VOICEVOX設定が外部で変わりました。再選択してください。');
        Temporary := FFileName+'.'+IntToHex(GetCurrentProcessId,8)+'.pending';
        var Ini := TMemIniFile.Create(FFileName,TEncoding.UTF8);
        try Ini.WriteString('VOICEVOX','EngineExe',Normalized); Ini.Rename(Temporary,False); Ini.UpdateFile; finally Ini.Free; end;
        var WrittenHash := THashSHA2.GetHashStringFromFile(Temporary);
        if not MoveFileEx(PChar(Temporary),PChar(FFileName),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
        FLoadedHash := WrittenHash; Result := True;
      finally Lock.Release; end;
    except on E: Exception do FLastError := 'アプリフォルダのVOICEVOX設定を保存できません: '+E.Message; end;
  finally if (Temporary<>'') and FileExists(Temporary) then TFile.Delete(Temporary); Lock.Free; end;
end;
end.
