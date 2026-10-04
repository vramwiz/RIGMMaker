unit SwitchProInput;

// Switch Pro Controller の HID 入力を非同期に読み取る。

interface

uses System.SysUtils, Winapi.Windows, GamepadState;

type
  TSwitchProDeviceInfo = record
    Path: string;
    InputLength, OutputLength, Usage, UsagePage: Word;
  end;

  TSwitchProInput = class
  private
    FHandle, FEvent: THandle;
    FOverlapped: TOverlapped;
    FPending, FHaveReport: Boolean;
    FReportLength: Cardinal;
    FBuffer: TBytes;
    FState: TGamepadState;
    FPressedButtons, FPressedPOV: Cardinal;
    FLastSearch: UInt64;
    FLastReportTick: UInt64;
    FDevicePath: string;
    FOutputReportLength: Word;
    FFullModeEnabled: Boolean;
    FPacketNumber: Byte;
    FManageReportMode, FSetPlayerLED: Boolean;
    FReportCount: UInt64;
    FLastReportId: Byte;
    procedure CloseDevice;
    function OpenDevice: Boolean;
    function StartRead: Boolean;
    function SetReportMode(const Path: string; OutputLength: Word;
      Mode: Byte): Boolean;
    procedure DecodeReport(Count: Cardinal);
    function GetConnected: Boolean;
  public
    // HID入力状態を未接続で初期化する。実デバイス探索はPoll時に行う。
    constructor Create(ManageReportMode: Boolean = True; SetPlayerLED: Boolean = True);
    // 読取とデバイスを閉じ、変更した報告モードを元へ戻す。
    destructor Destroy; override;
    // 最新報告と途中の短い押下を返す。未接続時は間隔を空けて再探索する。
    function Poll(out State: TGamepadState): Boolean;
    // 画面表示時に再探索待ちを省いて接続を試み、接続状態を返す。
    function ProbeConnection: Boolean;
    // HID接続を閉じ、次回Pollで再探索できるようにする。
    procedure Disconnect;
    // Read-only enumeration: does not change report mode or LEDs.
    class function EnumerateDevices: TArray<TSwitchProDeviceInfo>; overload; static;
    class function EnumerateDevices(out InterfaceCount: Integer;
      out EnumerationError: Cardinal): TArray<TSwitchProDeviceInfo>; overload; static;
    property Connected: Boolean read GetConnected;
    property DevicePath: string read FDevicePath;
    property ReportCount: UInt64 read FReportCount;
    property LastReportId: Byte read FLastReportId;
    property FullModeEnabled: Boolean read FFullModeEnabled;
  end;

implementation

uses SwitchProOutput, SwitchProReportDecoder, System.Generics.Collections;

const
  HidInterfaceGuid: TGUID = '{4D1E55B2-F16F-11CF-88CB-001111000030}';
  DigcfPresent = $02;
  DigcfDeviceInterface = $10;

type
  THidAttributes = record
    Size: Cardinal;
    VendorID, ProductID, VersionNumber: Word;
  end;
  THidCaps = record
    Usage, UsagePage, InputReportByteLength, OutputReportByteLength,
      FeatureReportByteLength: Word;
    Reserved: array[0..16] of Word;
    Remaining: array[0..9] of Word;
  end;
  TDeviceInterfaceData = record
    cbSize: Cardinal;
    InterfaceClassGuid: TGUID;
    Flags: Cardinal;
    Reserved: NativeUInt;
  end;

function SetupDiGetClassDevsW(ClassGuid: PGUID; Enumerator: PWideChar;
  hwndParent: HWND; Flags: Cardinal): THandle; stdcall; external 'setupapi.dll';
function SetupDiEnumDeviceInterfaces(DeviceInfoSet: THandle; DeviceInfoData: Pointer;
  InterfaceClassGuid: PGUID; MemberIndex: Cardinal;
  var DeviceInterfaceData: TDeviceInterfaceData): BOOL; stdcall; external 'setupapi.dll';
function SetupDiGetDeviceInterfaceDetailW(DeviceInfoSet: THandle;
  var DeviceInterfaceData: TDeviceInterfaceData; DeviceInterfaceDetailData: Pointer;
  DeviceInterfaceDetailDataSize: Cardinal; RequiredSize: PCardinal;
  DeviceInfoData: Pointer): BOOL; stdcall; external 'setupapi.dll';
function SetupDiDestroyDeviceInfoList(DeviceInfoSet: THandle): BOOL;
  stdcall; external 'setupapi.dll';
function HidD_GetAttributes(HidDeviceObject: THandle;
  var Attributes: THidAttributes): BOOL; stdcall; external 'hid.dll';
function HidD_GetPreparsedData(HidDeviceObject: THandle;
  var PreparsedData: Pointer): BOOL; stdcall; external 'hid.dll';
function HidD_FreePreparsedData(PreparsedData: Pointer): BOOL;
  stdcall; external 'hid.dll';
function HidP_GetCaps(PreparsedData: Pointer; var Capabilities: THidCaps): Longint;
  stdcall; external 'hid.dll';

constructor TSwitchProInput.Create(ManageReportMode, SetPlayerLED: Boolean);
begin
  inherited Create;
  FManageReportMode := ManageReportMode; FSetPlayerLED := SetPlayerLED;
  FHandle := INVALID_HANDLE_VALUE;
  FState.POV := $FFFF;
  FPressedPOV := $FFFF;
  FLastReportTick := 0;
end;

destructor TSwitchProInput.Destroy;
begin
  CloseDevice;
  inherited;
end;

procedure TSwitchProInput.CloseDevice;
begin
  if FHandle <> INVALID_HANDLE_VALUE then
  begin
    if FPending then
    begin
      CancelIoEx(FHandle, @FOverlapped);
      WaitForSingleObject(FEvent, 1000);
    end;
    // 自分で変更した入力方式だけを、Windowsの通常HID方式へ戻す。
    if FFullModeEnabled then
      SetReportMode(FDevicePath, FOutputReportLength, $3F);
    CloseHandle(FHandle);
  end;
  if FEvent <> 0 then CloseHandle(FEvent);
  FHandle := INVALID_HANDLE_VALUE;
  FEvent := 0;
  FPending := False;
  FHaveReport := False;
  FState := Default(TGamepadState);
  FState.POV := $FFFF;
  FPressedButtons := 0;
  FPressedPOV := $FFFF;
  FLastReportTick := 0;
  FBuffer := nil;
  FDevicePath := '';
  FOutputReportLength := 0;
  FFullModeEnabled := False;
  FPacketNumber := 0;
end;

function TSwitchProInput.SetReportMode(const Path: string;
  OutputLength: Word; Mode: Byte): Boolean;
begin
  Result := SendProSubcommand(Path, OutputLength,
    FPacketNumber, $03, Mode);
end;

function TSwitchProInput.OpenDevice: Boolean;
var
  DeviceSet, Candidate: THandle;
  Data: TDeviceInterfaceData;
  Detail: TBytes;
  Attr: THidAttributes;
  Caps: THidCaps;
  Prep: Pointer;
  Needed, Index: Cardinal;
begin
  Result := False;
  DeviceSet := SetupDiGetClassDevsW(@HidInterfaceGuid, nil, 0,
    DigcfPresent or DigcfDeviceInterface);
  if DeviceSet = INVALID_HANDLE_VALUE then Exit;
  try
    Index := 0;
    while True do
    begin
      FillChar(Data, SizeOf(Data), 0);
      Data.cbSize := SizeOf(Data);
      if not SetupDiEnumDeviceInterfaces(DeviceSet, nil, @HidInterfaceGuid,
        Index, Data) then Break;
      Inc(Index);
      Needed := 0;
      SetupDiGetDeviceInterfaceDetailW(DeviceSet, Data, nil, 0, @Needed, nil);
      if (Needed < 8) or (Needed > 65536) then Continue;
      SetLength(Detail, Needed);
      PCardinal(@Detail[0])^ := 8; // Win64 の detail.cbSize
      if not SetupDiGetDeviceInterfaceDetailW(DeviceSet, Data, @Detail[0],
        Needed, nil, nil) then Continue;
      Candidate := CreateFileW(PWideChar(@Detail[4]), GENERIC_READ,
        FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED, 0);
      if Candidate = INVALID_HANDLE_VALUE then Continue;
      FillChar(Attr, SizeOf(Attr), 0);
      Attr.Size := SizeOf(Attr);
      if not HidD_GetAttributes(Candidate, Attr) or
        (Attr.VendorID <> $057E) or (Attr.ProductID <> $2009) then
      begin
        CloseHandle(Candidate);
        Continue;
      end;
      Prep := nil;
      FillChar(Caps, SizeOf(Caps), 0);
      if not HidD_GetPreparsedData(Candidate, Prep) then
      begin
        CloseHandle(Candidate);
        Continue;
      end;
      try
        if HidP_GetCaps(Prep, Caps) < 0 then
        begin
          CloseHandle(Candidate);
          Continue;
        end;
      finally
        HidD_FreePreparsedData(Prep);
      end;
      if (Caps.InputReportByteLength < 12) or
        (Caps.InputReportByteLength > 4096) then
      begin
        CloseHandle(Candidate);
        Continue;
      end;
      FEvent := CreateEvent(nil, True, False, nil);
      if FEvent = 0 then
      begin
        CloseHandle(Candidate);
        Continue;
      end;
      FHandle := Candidate;
      FReportLength := Caps.InputReportByteLength;
      SetLength(FBuffer, FReportLength);
      FDevicePath := PWideChar(@Detail[4]);
      FOutputReportLength := Caps.OutputReportByteLength;
      FFullModeEnabled := False;
      if FManageReportMode then FFullModeEnabled := SetReportMode(FDevicePath,
        FOutputReportLength, $30);
      TraceProOutput('device_open',
        'input_length=' + IntToStr(FReportLength) +
        ' output_length=' + IntToStr(FOutputReportLength) +
        ' full_mode=' + BoolToStr(FFullModeEnabled, True));
      if StartRead then
      begin
        // HID接続後にプレイヤー1を点灯し、探索中の流れる表示を終える。
        if FSetPlayerLED then SendProSubcommand(FDevicePath, FOutputReportLength,
          FPacketNumber, $30, $01);
        Exit(True);
      end;
      CloseDevice;
    end;
  finally
    SetupDiDestroyDeviceInfoList(DeviceSet);
  end;
end;

function TSwitchProInput.StartRead: Boolean;
var Count: Cardinal;
begin
  FillChar(FOverlapped, SizeOf(FOverlapped), 0);
  FOverlapped.hEvent := FEvent;
  ResetEvent(FEvent);
  Count := 0;
  Result := ReadFile(FHandle, FBuffer[0], FReportLength, Count, @FOverlapped);
  if Result then
  begin
    FPending := False;
    DecodeReport(Count);
  end
  else
  begin
    FPending := GetLastError = ERROR_IO_PENDING;
    Result := FPending;
  end;
end;

procedure TSwitchProInput.DecodeReport(Count: Cardinal);
begin
  if DecodeProReport(FBuffer, Count, FState, FPressedButtons, FPressedPOV,
    FHaveReport) then begin
    FLastReportTick := GetTickCount64; Inc(FReportCount); FLastReportId := FBuffer[0];
  end;
end;

function TSwitchProInput.Poll(out State: TGamepadState): Boolean;
var Count: Cardinal; Index: Integer;
begin
  State := Default(TGamepadState);
  State.POV := $FFFF;
  if FHandle = INVALID_HANDLE_VALUE then
  begin
    if GetTickCount64 - FLastSearch < 1000 then Exit(False);
    FLastSearch := GetTickCount64;
    if not OpenDevice then Exit(False);
  end;
  for Index := 0 to 63 do
  begin
    if FPending then
    begin
      Count := 0;
      if not GetOverlappedResult(FHandle, FOverlapped, Count, False) then
      begin
        if GetLastError = ERROR_IO_INCOMPLETE then Break;
        CloseDevice;
        Exit(False);
      end;
      FPending := False;
      DecodeReport(Count);
    end;
    if not StartRead then
    begin
      CloseDevice;
      Exit(False);
    end;
    if FPending then Break;
  end;
  Result := FHaveReport;
  if Result then
  begin
    State := FState;
    State.Buttons := State.Buttons or FPressedButtons;
    if State.POV = $FFFF then State.POV := FPressedPOV;
    // HIDの新しい報告が途絶えたとき、最後のスティック入力を保持しない。
    if GetTickCount64 - FLastReportTick > 250 then
    begin
      State.LeftX := 0;
      State.LeftY := 0;
      State.RightX := 0;
      State.RightY := 0;
      State.Buttons := 0;
      State.POV := $FFFF;
    end;
  end;
  FPressedButtons := 0;
  FPressedPOV := $FFFF;
end;

function TSwitchProInput.GetConnected: Boolean;
begin
  Result := (FHandle <> INVALID_HANDLE_VALUE) and (FEvent <> 0);
end;

function TSwitchProInput.ProbeConnection: Boolean;
var
  State: TGamepadState;
begin
  // 明示的な画面切替では、定期探索の1秒待ちを飛ばして再接続を試す。
  if not Connected then FLastSearch := 0;
  Poll(State);
  Result := Connected;
end;

procedure TSwitchProInput.Disconnect;
begin
  CloseDevice;
  FLastSearch := 0;
end;

class function TSwitchProInput.EnumerateDevices: TArray<TSwitchProDeviceInfo>;
var InterfaceCount: Integer; EnumerationError: Cardinal;
begin Result := EnumerateDevices(InterfaceCount, EnumerationError); end;

class function TSwitchProInput.EnumerateDevices(out InterfaceCount: Integer;
  out EnumerationError: Cardinal): TArray<TSwitchProDeviceInfo>;
var DeviceSet, Handle: THandle; Data: TDeviceInterfaceData; Detail: TBytes;
    Attr: THidAttributes; Caps: THidCaps; Prep: Pointer; Needed, Index: Cardinal;
    Devices: TList<TSwitchProDeviceInfo>; Device: TSwitchProDeviceInfo;
begin
  Result := nil; InterfaceCount := 0; EnumerationError := 0; Devices := TList<TSwitchProDeviceInfo>.Create;
  try
    DeviceSet := SetupDiGetClassDevsW(@HidInterfaceGuid, nil, 0, DigcfPresent or DigcfDeviceInterface);
    if DeviceSet = INVALID_HANDLE_VALUE then begin EnumerationError := GetLastError; Exit; end;
    try
      Index := 0;
      while True do begin
        FillChar(Data, SizeOf(Data), 0); Data.cbSize := SizeOf(Data);
        if not SetupDiEnumDeviceInterfaces(DeviceSet, nil, @HidInterfaceGuid, Index, Data) then begin
          EnumerationError := GetLastError; if EnumerationError = ERROR_NO_MORE_ITEMS then EnumerationError := 0; Break;
        end;
        Inc(Index); Inc(InterfaceCount); Needed := 0; SetupDiGetDeviceInterfaceDetailW(DeviceSet, Data, nil, 0, @Needed, nil);
        if (Needed < 8) or (Needed > 65536) then Continue;
        SetLength(Detail, Needed); PCardinal(@Detail[0])^ := 8;
        if not SetupDiGetDeviceInterfaceDetailW(DeviceSet, Data, @Detail[0], Needed, nil, nil) then Continue;
        // Zero desired access allows querying attributes without reading or writing reports.
        Handle := CreateFileW(PWideChar(@Detail[4]), 0, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, 0, 0);
        if Handle = INVALID_HANDLE_VALUE then Continue;
        try
          FillChar(Attr, SizeOf(Attr), 0); Attr.Size := SizeOf(Attr);
          if not HidD_GetAttributes(Handle, Attr) or (Attr.VendorID <> $057E) or (Attr.ProductID <> $2009) then Continue;
          Prep := nil; if not HidD_GetPreparsedData(Handle, Prep) then Continue;
          try FillChar(Caps, SizeOf(Caps), 0); if HidP_GetCaps(Prep, Caps) < 0 then Continue;
          finally HidD_FreePreparsedData(Prep); end;
          Device := Default(TSwitchProDeviceInfo); Device.Path := PWideChar(@Detail[4]);
          Device.InputLength := Caps.InputReportByteLength; Device.OutputLength := Caps.OutputReportByteLength;
          Device.Usage := Caps.Usage; Device.UsagePage := Caps.UsagePage; Devices.Add(Device);
        finally CloseHandle(Handle); end;
      end;
    finally SetupDiDestroyDeviceInfoList(DeviceSet); end;
    Result := Devices.ToArray;
  finally Devices.Free; end;
end;

end.
