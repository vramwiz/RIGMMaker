// BGRA映像と同一レートのmono PCM16をH.264/AAC MP4へ逐次出力する。UI・作品・外部EXEに依存しない。
unit RigmFFmpegWriter;
interface
uses System.SysUtils, Vcl.Graphics, RigmFFmpegApi, RigmFFmpegTypes;
type
  TRigmFFmpegWriter = class
  private
    FApi: TRigmFFmpegApi;                 // DLLと関数の所有者。各FFmpegリソースを解放した後で破棄する。
    FFormat: PAVFormatContext;            // 所有するMP4 muxerとファイルI/O。
    FVideo,FAudio: PAVCodecContext;       // 所有するH.264/AACエンコーダー。
    FVideoStream,FAudioStream: PAVStream;  // FFormatが所有する映像・音声ストリーム。
    FVideoFrame,FAudioFrame: PAVFrame;     // 所有する再利用フレーム。各送信前にmake_writableする。
    FPacket: PAVPacket;                   // 所有する受信パケット。書込後は参照を解除する。
    FScale: PSwsContext;                  // 所有するBGRA→YUV420P変換。
    FPath: string;
    FWidth,FHeight,FFps,FRate,FAudioFrameSamples: Integer;
    FVideoPosition,FAudioPosition: Int64;  // 送信済みフレーム数・音声サンプル数。各streamのPTSに使う。
    FOwnsFile,FFinished: Boolean;         // 新規確保した出力だけを失敗・中止時に削除する。
    procedure OpenVideo(const Profile: string);
    procedure OpenAudio;
    procedure Drain(Codec: PAVCodecContext; Stream: PAVStream; Flushing: Boolean);
    procedure Send(Codec: PAVCodecContext; Stream: PAVStream; Frame: PAVFrame);
  public
    // 出力を新規作成する。既存ファイルは拒否し、DLL/codec/stream/frameを自身で所有する。
    constructor Create(const Path: string; Width,Height,Fps,AudioRate: Integer; const Profile: string);
    // 未完了の出力は削除する。入力Bitmap・PCM配列は所有しない。
    destructor Destroy; override;
    // Bitmapを同期変換・送信する。元のピクセル形式と寸法は変更しない。
    procedure AddVideo(Bitmap: Vcl.Graphics.TBitmap);
    // OffsetからCountサンプルを送信する。最後の端数以外はAudioFrameSamples単位とする。
    procedure AddAudio(const Samples: TArray<SmallInt>; Offset,Count: Integer);
    // 残りのpacketとMP4末尾・faststartを出力し、ファイルハンドルを閉じる。
    procedure Finish;
    property AudioFrameSamples: Integer read FAudioFrameSamples;
  end;
implementation
uses Winapi.Windows, System.Math, System.IOUtils;
const SampleFormatFltp = 8; // FFmpeg 8.1.1 AV_SAMPLE_FMT_FLTP: mono planar float。
procedure RequireAllocated(Value: Pointer; const Name: string);
begin if Value=nil then raise Exception.Create('MP4出力のメモリーを確保できません: '+Name); end;
constructor TRigmFFmpegWriter.Create(const Path: string; Width,Height,Fps,AudioRate: Integer; const Profile: string);
begin
  inherited Create;
  if (Width<=0) or (Height<=0) or Odd(Width) or Odd(Height) or (Fps<=0) or (AudioRate<>48000) then
    raise Exception.Create('MP4には偶数の映像寸法と48000 Hzの音声が必要です。');
  FPath := Path; FWidth := Width; FHeight := Height; FFps := Fps; FRate := AudioRate;
  FApi := TRigmFFmpegApi.Create;
  var Utf8Path := UTF8String(Path);
  FApi.Check(FApi.avformat_alloc_output_context2(@FFormat,nil,'mp4',PAnsiChar(Utf8Path)),'MP4 muxer');
  RequireAllocated(FFormat,'format');
  OpenVideo(Profile); OpenAudio;
  FPacket := FApi.av_packet_alloc(); RequireAllocated(FPacket,'packet');
  FScale := FApi.sws_getContext(FWidth,FHeight,FApi.av_get_pix_fmt('bgra'),FWidth,FHeight,
    FApi.av_get_pix_fmt('yuv420p'),SWS_BILINEAR,nil,nil,nil); RequireAllocated(FScale,'color conversion');
  FApi.Check(FApi.av_opt_set(FFormat^.priv_data,'movflags','+faststart',0),'MP4 faststart');
  // CREATE_NEWで予約できたファイルのみ、失敗時の削除対象とする。
  var Reservation := CreateFile(PChar(Path),GENERIC_WRITE,FILE_SHARE_READ or FILE_SHARE_WRITE,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  if Reservation=INVALID_HANDLE_VALUE then RaiseLastOSError;
  FOwnsFile := True; CloseHandle(Reservation);
  FApi.Check(FApi.avio_open(@FFormat^.pb,PAnsiChar(Utf8Path),AVIO_FLAG_WRITE),'MP4 file');
  FApi.Check(FApi.avformat_write_header(FFormat,nil),'MP4 header');
end;
procedure TRigmFFmpegWriter.OpenVideo(const Profile: string);
begin
  var Codec := FApi.avcodec_find_encoder_by_name('libx264'); RequireAllocated(Codec,'libx264');
  FVideo := FApi.avcodec_alloc_context3(Codec); RequireAllocated(FVideo,'video codec');
  var Context := PAVCodecContextPublic(FVideo);
  Context^.width := FWidth; Context^.height := FHeight;
  Context^.time_base.num := 1; Context^.time_base.den := FFps;
  Context^.framerate.num := FFps; Context^.framerate.den := 1;
  Context^.pix_fmt := FApi.av_get_pix_fmt('yuv420p'); Context^.max_b_frames := 0;
  Context^.flags := Context^.flags or AV_CODEC_FLAG_GLOBAL_HEADER;
  var Preset: AnsiString; var Quality: AnsiString;
  if Profile='fast' then begin Preset := 'veryfast'; Quality := '23'; end
  else if Profile='balanced' then begin Preset := 'medium'; Quality := '20'; end
  else if Profile='quality' then begin Preset := 'slow'; Quality := '18'; end
  else raise Exception.Create('出力品質はfast、balanced、qualityです。');
  FApi.Check(FApi.av_opt_set(Context^.priv_data,'preset',PAnsiChar(Preset),0),'H.264 preset');
  FApi.Check(FApi.av_opt_set(Context^.priv_data,'crf',PAnsiChar(Quality),0),'H.264 quality');
  FApi.Check(FApi.av_opt_set_int(FVideo,'threads',4,0),'H.264 threads');
  FApi.Check(FApi.avcodec_open2(FVideo,Codec,nil),'H.264 encoder');
  FVideoStream := FApi.avformat_new_stream(FFormat,nil); RequireAllocated(FVideoStream,'video stream');
  FVideoStream^.time_base := Context^.time_base;
  FVideoStream^.avg_frame_rate := Context^.framerate;
  FApi.Check(FApi.avcodec_parameters_from_context(FVideoStream^.codecpar,FVideo),'H.264 parameters');
  FVideoFrame := FApi.av_frame_alloc(); RequireAllocated(FVideoFrame,'video frame');
  FVideoFrame^.format := Context^.pix_fmt; FVideoFrame^.width := FWidth; FVideoFrame^.height := FHeight;
  FApi.Check(FApi.av_frame_get_buffer(FVideoFrame,32),'video frame buffer');
end;
procedure TRigmFFmpegWriter.OpenAudio;
begin
  var Codec := FApi.avcodec_find_encoder_by_name('aac'); RequireAllocated(Codec,'aac');
  FAudio := FApi.avcodec_alloc_context3(Codec); RequireAllocated(FAudio,'audio codec');
  var Context := PAVCodecContextPublic(FAudio);
  Context^.sample_rate := FRate; Context^.sample_fmt := SampleFormatFltp; Context^.bit_rate := 160000;
  Context^.time_base.num := 1; Context^.time_base.den := FRate;
  Context^.flags := Context^.flags or AV_CODEC_FLAG_GLOBAL_HEADER;
  FApi.av_channel_layout_default(@Context^.ch_layout,1);
  FApi.Check(FApi.avcodec_open2(FAudio,Codec,nil),'AAC encoder');
  FAudioFrameSamples := Context^.frame_size;
  if FAudioFrameSamples<=0 then raise Exception.Create('AACフレーム長が不正です。');
  FAudioStream := FApi.avformat_new_stream(FFormat,nil); RequireAllocated(FAudioStream,'audio stream');
  FAudioStream^.time_base := Context^.time_base;
  FApi.Check(FApi.avcodec_parameters_from_context(FAudioStream^.codecpar,FAudio),'AAC parameters');
  FAudioFrame := FApi.av_frame_alloc(); RequireAllocated(FAudioFrame,'audio frame');
  var Frame := PAVFrameAudioPublic(FAudioFrame);
  Frame^.format := SampleFormatFltp; Frame^.sample_rate := FRate; Frame^.nb_samples := FAudioFrameSamples;
  FApi.Check(FApi.av_channel_layout_copy(@Frame^.ch_layout,@Context^.ch_layout),'AAC channel layout');
  FApi.Check(FApi.av_frame_get_buffer(FAudioFrame,0),'audio frame buffer');
end;
procedure TRigmFFmpegWriter.Drain(Codec: PAVCodecContext; Stream: PAVStream; Flushing: Boolean);
begin
  while True do begin
    var Code := FApi.avcodec_receive_packet(Codec,FPacket);
    if Code=AVERROR_EOF then Exit;
    if Code=AVERROR_EAGAIN then begin
      if Flushing then raise Exception.Create('MP4圧縮の完了前に追加フレームが要求されました。');
      Exit;
    end;
    FApi.Check(Code,'encoded packet');
    try
      // 最終映像packetの長さも1フレーム。0のままだとMP4の末尾フレームが再生対象から落ちる。
      if (Stream=FVideoStream) and (FPacket^.duration<=0) then FPacket^.duration := 1;
      FApi.av_packet_rescale_ts(FPacket,PAVCodecContextPublic(Codec)^.time_base,Stream^.time_base);
      FPacket^.stream_index := Stream^.index;
      FApi.Check(FApi.av_interleaved_write_frame(FFormat,FPacket),'MP4 packet');
    finally FApi.av_packet_unref(FPacket); end;
  end;
end;
procedure TRigmFFmpegWriter.Send(Codec: PAVCodecContext; Stream: PAVStream; Frame: PAVFrame);
begin
  var Code := FApi.avcodec_send_frame(Codec,Frame);
  if Code=AVERROR_EAGAIN then begin Drain(Codec,Stream,False); Code := FApi.avcodec_send_frame(Codec,Frame); end;
  FApi.Check(Code,'encoder frame'); Drain(Codec,Stream,Frame=nil);
end;
procedure TRigmFFmpegWriter.AddVideo(Bitmap: Vcl.Graphics.TBitmap);
var Data: array[0..7] of PByte; Stride: array[0..7] of Integer;
begin
  if FFinished then raise Exception.Create('MP4出力は完了しています。');
  if (Bitmap.Width<>FWidth) or (Bitmap.Height<>FHeight) or (Bitmap.PixelFormat<>pf32bit) then
    raise Exception.Create('MP4のBGRAフレーム寸法・形式が一致しません。');
  FApi.Check(FApi.av_frame_make_writable(FVideoFrame),'writable video frame');
  GdiFlush;
  FillChar(Data,SizeOf(Data),0); FillChar(Stride,SizeOf(Stride),0);
  // VCLはScanLine[0]を上端にそろえる。DIBの格納方向は実際の行間差から得る。
  Data[0] := Bitmap.ScanLine[0]; Stride[0] := NativeInt(Bitmap.ScanLine[1])-NativeInt(Data[0]);
  var Rows := FApi.sws_scale(FScale,@Data[0],@Stride[0],0,FHeight,@FVideoFrame^.data[0],@FVideoFrame^.linesize[0]);
  if Rows<>FHeight then raise Exception.Create('MP4の色変換行数が一致しません。');
  FVideoFrame^.pts := FVideoPosition; Send(FVideo,FVideoStream,FVideoFrame); Inc(FVideoPosition);
end;
procedure TRigmFFmpegWriter.AddAudio(const Samples: TArray<SmallInt>; Offset,Count: Integer);
begin
  if FFinished or (Count<=0) or (Count>FAudioFrameSamples) or (Offset<0) or (Offset>Length(Samples)-Count) then
    raise Exception.Create('MP4音声サンプルの範囲が不正です。');
  var Frame := PAVFrameAudioPublic(FAudioFrame); Frame^.nb_samples := FAudioFrameSamples;
  FApi.Check(FApi.av_frame_make_writable(FAudioFrame),'writable audio frame');
  for var I := 0 to Count-1 do PSingle(NativeUInt(Frame^.data[0])+NativeUInt(I)*SizeOf(Single))^ := Samples[Offset+I]/32768.0;
  Frame^.nb_samples := Count; Frame^.pts := FAudioPosition;
  Send(FAudio,FAudioStream,FAudioFrame); Inc(FAudioPosition,Count);
end;
procedure TRigmFFmpegWriter.Finish;
begin
  if FFinished then Exit;
  Send(FVideo,FVideoStream,nil); Send(FAudio,FAudioStream,nil);
  FApi.Check(FApi.av_write_trailer(FFormat),'MP4 trailer');
  FApi.Check(FApi.avio_closep(@FFormat^.pb),'MP4 close');
  if TFile.GetSize(FPath)=0 then raise Exception.Create('MP4出力が空です。');
  FFinished := True;
end;
destructor TRigmFFmpegWriter.Destroy;
begin
  if FApi<>nil then begin
    if FFormat<>nil then begin if FFormat^.pb<>nil then FApi.avio_closep(@FFormat^.pb); FApi.avformat_free_context(FFormat); end;
    if FScale<>nil then FApi.sws_freeContext(FScale);
    if FPacket<>nil then FApi.av_packet_free(@FPacket);
    if FVideoFrame<>nil then FApi.av_frame_free(@FVideoFrame);
    if FAudioFrame<>nil then FApi.av_frame_free(@FAudioFrame);
    if FVideo<>nil then FApi.avcodec_free_context(@FVideo);
    if FAudio<>nil then FApi.avcodec_free_context(@FAudio);
    FApi.Free;
  end;
  if FOwnsFile and not FFinished and FileExists(FPath) then TFile.Delete(FPath);
  inherited;
end;
end.
