// 同梱したFFmpeg 8.1.1のDLLと関数をジョブごとに所有する。検索場所やプロセス全体のDLL設定を変えない。
unit RigmFFmpegApi;
interface
uses Winapi.Windows, System.SysUtils, System.Math, RigmFFmpegTypes;
type
  TRigmFFmpegApi = class
  private
    FModules: array[0..4] of HMODULE; // util / resample / scale / codec / formatの所有参照。
    FExceptionMask: TArithmeticExceptionMask; // Cライブラリ呼出中だけ、作成スレッドの浮動小数点例外を抑える。
    FMaskSaved: Boolean;
    function Proc(Module: Integer; const Name: AnsiString): Pointer;
    procedure CheckVersion(Module,Major: Integer; const Name: AnsiString);
  public
    avformat_alloc_output_context2: Tavformat_alloc_output_context2;
    avformat_new_stream: Tavformat_new_stream;
    avformat_write_header: Tavformat_write_header;
    av_interleaved_write_frame: Tav_interleaved_write_frame;
    av_write_trailer: Tav_write_trailer;
    avformat_free_context: Tavformat_free_context;
    avio_open: Tavio_open;
    avio_closep: Tavio_closep;
    avcodec_find_encoder_by_name: Tavcodec_find_encoder_by_name;
    avcodec_alloc_context3: Tavcodec_alloc_context3;
    avcodec_parameters_from_context: Tavcodec_parameters_from_context;
    avcodec_open2: Tavcodec_open2;
    avcodec_free_context: Tavcodec_free_context;
    avcodec_send_frame: Tavcodec_send_frame;
    avcodec_receive_packet: Tavcodec_receive_packet;
    av_packet_alloc: Tav_packet_alloc;
    av_packet_free: Tav_packet_free;
    av_packet_unref: Tav_packet_unref;
    av_packet_rescale_ts: Tav_packet_rescale_ts;
    av_frame_alloc: Tav_frame_alloc;
    av_frame_free: Tav_frame_free;
    av_frame_get_buffer: Tav_frame_get_buffer;
    av_frame_make_writable: Tav_frame_make_writable;
    av_strerror: Tav_strerror;
    av_get_pix_fmt: Tav_get_pix_fmt;
    av_opt_set: Tav_opt_set;
    av_opt_set_int: Tav_opt_set_int;
    av_channel_layout_default: Tav_channel_layout_default;
    av_channel_layout_copy: Tav_channel_layout_copy;
    av_channel_layout_uninit: Tav_channel_layout_uninit;
    sws_getContext: Tsws_getContext;
    sws_scale: Tsws_scale;
    sws_freeContext: Tsws_freeContext;
    // 読込・再生検証にも同じ版のAPIを利用できる。作品やUIは参照しない。
    avformat_open_input: Tavformat_open_input;
    avformat_find_stream_info: Tavformat_find_stream_info;
    avformat_close_input: Tavformat_close_input;
    av_read_frame: Tav_read_frame;
    avcodec_find_decoder: Tavcodec_find_decoder;
    avcodec_parameters_to_context: Tavcodec_parameters_to_context;
    avcodec_send_packet: Tavcodec_send_packet;
    avcodec_receive_frame: Tavcodec_receive_frame;
    // EXE隣のRuntime/FFmpegだけを読み、関数とABI majorを検査する。作成・呼出・破棄は同一スレッド。
    constructor Create;
    destructor Destroy; override;
    // 負のFFmpeg戻り値を操作名付きの例外へ変換する。
    procedure Check(Code: Integer; const Operation: string);
  end;
// カレントディレクトリやPATHに依存しない、同梱DLLの絶対ディレクトリ。
function BundledFFmpegDirectory: string;
// 読取診断用。5 DLLの存在だけを調べ、ロードやファイル生成は行わない。
function BundledFFmpegAvailable: Boolean;
implementation
uses System.IOUtils;
const
  DllNames: array[0..4] of string = ('avutil-60.dll','swresample-6.dll','swscale-9.dll','avcodec-62.dll','avformat-62.dll');
  SearchDllLoadDir = $00000100; // Windows LoadLibraryEx: DLL本体の絶対ディレクトリから依存を探す。
  SearchDefaultDirs = $00001000; // Windows LoadLibraryEx: アプリ・System32などの安全な既定検索。
function BundledFFmpegDirectory: string;
begin Result := TPath.Combine(ExtractFilePath(ParamStr(0)),'Runtime\FFmpeg'); end;
function BundledFFmpegAvailable: Boolean;
begin
  Result := True;
  for var Name in DllNames do if not FileExists(TPath.Combine(BundledFFmpegDirectory,Name)) then Exit(False);
end;
function TRigmFFmpegApi.Proc(Module: Integer; const Name: AnsiString): Pointer;
begin
  Result := GetProcAddress(FModules[Module],PAnsiChar(Name));
  if Result=nil then raise Exception.Create('同梱FFmpegに必要な関数がありません: '+string(Name));
end;
procedure TRigmFFmpegApi.CheckVersion(Module,Major: Integer; const Name: AnsiString);
type TVersion = function: Cardinal; cdecl;
var Version: TVersion;
begin
  Version := TVersion(Proc(Module,Name));
  if (Version() shr 16)<>Cardinal(Major) then raise Exception.Create('同梱FFmpeg DLLのバージョンが一致しません: '+DllNames[Module]);
end;
constructor TRigmFFmpegApi.Create;
begin
  inherited;
  FExceptionMask := SetExceptionMask([exInvalidOp,exDenormalized,exZeroDivide,exOverflow,exUnderflow,exPrecision]);
  FMaskSaved := True;
  for var I := 0 to High(FModules) do begin
    var Path := TPath.Combine(BundledFFmpegDirectory,DllNames[I]);
    if not FileExists(Path) then raise Exception.Create('MP4出力用の同梱DLLがありません: '+Path);
    FModules[I] := LoadLibraryEx(PChar(Path),0,SearchDllLoadDir or SearchDefaultDirs);
    if FModules[I]=0 then raise Exception.Create('MP4出力用DLLを読み込めません: '+Path+sLineBreak+SysErrorMessage(GetLastError));
  end;
  CheckVersion(0,60,'avutil_version'); CheckVersion(1,6,'swresample_version');
  CheckVersion(2,9,'swscale_version'); CheckVersion(3,62,'avcodec_version'); CheckVersion(4,62,'avformat_version');
  avformat_alloc_output_context2 := Tavformat_alloc_output_context2(Proc(4,'avformat_alloc_output_context2'));
  avformat_new_stream := Tavformat_new_stream(Proc(4,'avformat_new_stream'));
  avformat_write_header := Tavformat_write_header(Proc(4,'avformat_write_header'));
  av_interleaved_write_frame := Tav_interleaved_write_frame(Proc(4,'av_interleaved_write_frame'));
  av_write_trailer := Tav_write_trailer(Proc(4,'av_write_trailer'));
  avformat_free_context := Tavformat_free_context(Proc(4,'avformat_free_context'));
  avio_open := Tavio_open(Proc(4,'avio_open')); avio_closep := Tavio_closep(Proc(4,'avio_closep'));
  avcodec_find_encoder_by_name := Tavcodec_find_encoder_by_name(Proc(3,'avcodec_find_encoder_by_name'));
  avcodec_alloc_context3 := Tavcodec_alloc_context3(Proc(3,'avcodec_alloc_context3'));
  avcodec_parameters_from_context := Tavcodec_parameters_from_context(Proc(3,'avcodec_parameters_from_context'));
  avcodec_open2 := Tavcodec_open2(Proc(3,'avcodec_open2')); avcodec_free_context := Tavcodec_free_context(Proc(3,'avcodec_free_context'));
  avcodec_send_frame := Tavcodec_send_frame(Proc(3,'avcodec_send_frame'));
  avcodec_receive_packet := Tavcodec_receive_packet(Proc(3,'avcodec_receive_packet'));
  av_packet_alloc := Tav_packet_alloc(Proc(3,'av_packet_alloc')); av_packet_free := Tav_packet_free(Proc(3,'av_packet_free'));
  av_packet_unref := Tav_packet_unref(Proc(3,'av_packet_unref')); av_packet_rescale_ts := Tav_packet_rescale_ts(Proc(3,'av_packet_rescale_ts'));
  av_frame_alloc := Tav_frame_alloc(Proc(0,'av_frame_alloc')); av_frame_free := Tav_frame_free(Proc(0,'av_frame_free'));
  av_frame_get_buffer := Tav_frame_get_buffer(Proc(0,'av_frame_get_buffer'));
  av_frame_make_writable := Tav_frame_make_writable(Proc(0,'av_frame_make_writable'));
  av_strerror := Tav_strerror(Proc(0,'av_strerror')); av_get_pix_fmt := Tav_get_pix_fmt(Proc(0,'av_get_pix_fmt'));
  av_opt_set := Tav_opt_set(Proc(0,'av_opt_set')); av_opt_set_int := Tav_opt_set_int(Proc(0,'av_opt_set_int'));
  av_channel_layout_default := Tav_channel_layout_default(Proc(0,'av_channel_layout_default'));
  av_channel_layout_copy := Tav_channel_layout_copy(Proc(0,'av_channel_layout_copy'));
  av_channel_layout_uninit := Tav_channel_layout_uninit(Proc(0,'av_channel_layout_uninit'));
  sws_getContext := Tsws_getContext(Proc(2,'sws_getContext')); sws_scale := Tsws_scale(Proc(2,'sws_scale'));
  sws_freeContext := Tsws_freeContext(Proc(2,'sws_freeContext'));
  avformat_open_input := Tavformat_open_input(Proc(4,'avformat_open_input'));
  avformat_find_stream_info := Tavformat_find_stream_info(Proc(4,'avformat_find_stream_info'));
  avformat_close_input := Tavformat_close_input(Proc(4,'avformat_close_input')); av_read_frame := Tav_read_frame(Proc(4,'av_read_frame'));
  avcodec_find_decoder := Tavcodec_find_decoder(Proc(3,'avcodec_find_decoder'));
  avcodec_parameters_to_context := Tavcodec_parameters_to_context(Proc(3,'avcodec_parameters_to_context'));
  avcodec_send_packet := Tavcodec_send_packet(Proc(3,'avcodec_send_packet'));
  avcodec_receive_frame := Tavcodec_receive_frame(Proc(3,'avcodec_receive_frame'));
end;
destructor TRigmFFmpegApi.Destroy;
begin
  try
    for var I := High(FModules) downto 0 do if FModules[I]<>0 then FreeLibrary(FModules[I]);
  finally
    if FMaskSaved then begin ClearExceptions; SetExceptionMask(FExceptionMask); end;
    inherited;
  end;
end;
procedure TRigmFFmpegApi.Check(Code: Integer; const Operation: string);
begin
  if Code>=0 then Exit;
  var Buffer: array[0..255] of AnsiChar;
  Buffer[0] := #0; av_strerror(Code,@Buffer[0],Length(Buffer));
  raise Exception.Create(Operation+': '+string(UTF8String(PAnsiChar(@Buffer[0]))));
end;
end.
