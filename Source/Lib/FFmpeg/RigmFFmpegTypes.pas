// FFmpeg 8.1.1 Win64 ABI。VM_Media_Outputの定義を対応する公式ヘッダーと照合して使用する。
// 元の構造体を部分定義し、FFmpegが確保した領域だけを参照する。Delphi側でrecordを確保しない。
unit RigmFFmpegTypes;
interface
uses Winapi.Windows;
{$ALIGN 8}
type
  TAVMediaType = Integer;

  PAVPacketSideData = ^TAVPacketSideData;
  PPAVPacketSideData = ^PAVPacketSideData;
  // FFmpegのpacket/stream side data。
  TAVPacketSideData = record
    data      : PByte;      // side data本体
    size      : NativeUInt; // side dataサイズ
    data_type : Integer;    // AVPacketSideDataType
  end;

  // FFmpegの分数値を表す型。
  TAVRational = record
    num : Integer; // 分子
    den : Integer; // 分母
  end;

  PAVCodecParameters = ^TAVCodecParameters;
  PAVChannelLayout = ^TAVChannelLayout;
  // FFmpegのチャンネルレイアウト情報。
  TAVChannelLayout = record
    order       : Integer; // レイアウト表現方式
    nb_channels : Integer; // チャンネル数
    u           : UInt64;  // FFmpeg側のレイアウト値
    opaque      : Pointer; // FFmpeg内部用ポインタ
  end;

  // FFmpegストリームのコーデック基本情報。
  TAVCodecParameters = record
    codec_type             : TAVMediaType;     // 映像/音声などのメディア種別
    codec_id               : Integer;          // FFmpegのコーデックID
    codec_tag              : Cardinal;         // コンテナ側のコーデックタグ
    extradata              : PByte;            // デコーダ初期化用の追加データ
    extradata_size         : Integer;          // 追加データのバイト数
    coded_side_data        : PAVPacketSideData; // FFmpeg側のサイドデータ
    nb_coded_side_data     : Integer;          // サイドデータ数
    format                 : Integer;          // ピクセル形式またはサンプル形式
    bit_rate               : Int64;            // ビットレート
    bits_per_coded_sample  : Integer;          // 符号化サンプルあたりビット数
    bits_per_raw_sample    : Integer;          // 生サンプルあたりビット数
    profile                : Integer;          // コーデックプロファイル
    level                  : Integer;          // コーデックレベル
    width                  : Integer;          // 映像幅
    height                 : Integer;          // 映像高さ
    sample_aspect_ratio    : TAVRational;      // サンプルアスペクト比
    framerate              : TAVRational;      // ストリーム側のフレームレート
    field_order            : Integer;          // フィールド順
    color_range            : Integer;          // 色範囲
    color_primaries        : Integer;          // 色域
    color_trc              : Integer;          // 伝達特性
    color_space            : Integer;          // 色空間
    chroma_location        : Integer;          // クロマ位置
    video_delay            : Integer;          // 映像デコード遅延
    ch_layout              : TAVChannelLayout; // 音声チャンネルレイアウト
    sample_rate            : Integer;          // 音声サンプルレート
    block_align            : Integer;          // 音声ブロック境界
    frame_size             : Integer;          // 音声フレームサイズ
    initial_padding        : Integer;          // 先頭パディング
    trailing_padding       : Integer;          // 末尾パディング
    seek_preroll           : Integer;          // シーク後に必要なプリロール
  end;

  PAVStream = ^TAVStream;
  PPAVStream = ^PAVStream;
  // FFmpegの入力ストリーム情報。
  TAVStream = record
    av_class            : Pointer;                    // FFmpeg内部クラス情報
    index               : Integer;                    // ストリーム番号
    id                  : Integer;                    // コンテナ内のストリームID
    codecpar            : PAVCodecParameters;         // コーデック情報
    priv_data           : Pointer;                    // FFmpeg内部用データ
    time_base           : TAVRational;                // PTS/DTSの時間単位
    start_time          : Int64;                      // 開始時刻
    duration            : Int64;                      // ストリーム長
    nb_frames           : Int64;                      // フレーム数
    disposition         : Integer;                    // ストリーム属性
    discard             : Integer;                    // 破棄設定
    sample_aspect_ratio : TAVRational;                // サンプルアスペクト比
    metadata            : Pointer;                    // メタデータ
    avg_frame_rate      : TAVRational;                // 平均フレームレート
    attached_pic        : array[0..103] of Byte;      // 添付画像情報の予約領域
    event_flags         : Integer;                    // FFmpegイベントフラグ
    r_frame_rate        : TAVRational;                // 推定フレームレート
    pts_wrap_bits       : Integer;                    // PTS折り返しビット数
  end;

  PAVFormatContext = ^TAVFormatContext;
  PPAVFormatContext = ^PAVFormatContext;
  // FFmpegの入力フォーマットコンテキスト。
  TAVFormatContext = record
    av_class         : Pointer;     // FFmpeg内部クラス情報
    iformat          : Pointer;     // 入力フォーマット
    oformat          : Pointer;     // 出力フォーマット
    priv_data        : Pointer;     // FFmpeg内部用データ
    pb               : Pointer;     // I/Oコンテキスト
    ctx_flags        : Integer;     // コンテキストフラグ
    nb_streams       : Cardinal;    // ストリーム数
    streams          : PPAVStream;  // ストリーム配列
    nb_stream_groups : Cardinal;    // ストリームグループ数
    stream_groups    : Pointer;     // ストリームグループ配列
    nb_chapters      : Cardinal;    // チャプター数
    chapters         : Pointer;     // チャプター配列
    url              : PAnsiChar;   // 入力URL
    start_time       : Int64;       // 入力全体の開始時刻
    duration         : Int64;       // 入力全体の長さ
  end;

  PAVCodec = Pointer;
  PAVCodecContext = Pointer;
  PPAVCodecContext = ^PAVCodecContext;
  PSwsContext = Pointer;
  PSwrContext = Pointer;
  PPSwrContext = ^PSwrContext;

  PAVPacket = ^TAVPacket;
  PPAVPacket = ^PAVPacket;
  // FFmpegから読み込む圧縮済みパケット。
  TAVPacket = record
    buf             : Pointer;     // FFmpeg内部バッファ参照
    pts             : Int64;       // 表示時刻
    dts             : Int64;       // デコード時刻
    data            : PByte;       // パケットデータ
    size            : Integer;     // パケットデータのバイト数
    stream_index    : Integer;     // 所属ストリーム番号
    flags           : Integer;     // パケットフラグ
    side_data       : Pointer;     // サイドデータ
    side_data_elems : Integer;     // サイドデータ数
    duration        : Int64;       // パケットの長さ
    pos             : Int64;       // 入力内の位置
    opaque          : Pointer;     // FFmpeg内部用ポインタ
    opaque_ref      : Pointer;     // FFmpeg内部用参照
    time_base       : TAVRational; // パケット時刻の時間単位
  end;

  PAVFrame = ^TAVFrame;
  PPAVFrame = ^PAVFrame;
  // FFmpegがデコードした映像/音声フレーム。
  TAVFrame = record
    data                : array[0..7] of PByte;   // フレームデータのプレーンポインタ
    linesize            : array[0..7] of Integer; // 各プレーンの1行バイト数
    extended_data       : Pointer;                // 音声などで使う拡張プレーン
    width               : Integer;                // 映像幅
    height              : Integer;                // 映像高さ
    nb_samples          : Integer;                // 音声サンプル数
    format              : Integer;                // ピクセル形式またはサンプル形式
    pict_type           : Integer;                // 映像フレーム種別
    sample_aspect_ratio : TAVRational;            // サンプルアスペクト比
    pts                 : Int64;                  // フレームの表示時刻
  end;

  Tavformat_open_input           = function(ps: PPAVFormatContext; url: PAnsiChar;
    fmt: Pointer; options: Pointer): Integer; cdecl;
  Tavformat_find_stream_info     = function(ic: PAVFormatContext;
    options: Pointer): Integer; cdecl;
  Tavformat_close_input          = procedure(ps: PPAVFormatContext); cdecl;
  Tavformat_network_init         = function: Integer; cdecl;
  Tav_find_best_stream           = function(ic: PAVFormatContext; media_type: Integer;
    wanted_stream_nb: Integer; related_stream: Integer; decoder_ret: Pointer;
    flags: Integer): Integer; cdecl;
  Tav_read_frame                 = function(s: PAVFormatContext;
    pkt: PAVPacket): Integer; cdecl;
  Tav_seek_frame                 = function(s: PAVFormatContext; stream_index: Integer;
    timestamp: Int64; flags: Integer): Integer; cdecl;
  Tavformat_alloc_output_context2 = function(ctx: PPAVFormatContext;
    oformat: Pointer; format_name, filename: PAnsiChar): Integer; cdecl;
  Tavformat_new_stream           = function(ctx: PAVFormatContext;
    codec: PAVCodec): PAVStream; cdecl;
  Tavformat_write_header         = function(ctx: PAVFormatContext;
    options: Pointer): Integer; cdecl;
  Tav_interleaved_write_frame    = function(ctx: PAVFormatContext;
    pkt: PAVPacket): Integer; cdecl;
  Tav_write_trailer              = function(ctx: PAVFormatContext): Integer; cdecl;
  Tavformat_free_context         = procedure(ctx: PAVFormatContext); cdecl;
  Tavio_open                     = function(s: PPointer; url: PAnsiChar;
    flags: Integer): Integer; cdecl;
  Tavio_closep                   = function(s: PPointer): Integer; cdecl;

  Tavcodec_find_decoder          = function(id: Integer): PAVCodec; cdecl;
  Tavcodec_find_encoder_by_name  = function(name: PAnsiChar): PAVCodec; cdecl;
  Tavcodec_alloc_context3        = function(codec: PAVCodec): PAVCodecContext; cdecl;
  Tavcodec_parameters_to_context = function(codecContext: PAVCodecContext;
    codecpar: PAVCodecParameters): Integer; cdecl;
  Tavcodec_parameters_from_context = function(codecpar: PAVCodecParameters;
    codecContext: PAVCodecContext): Integer; cdecl;
  Tavcodec_open2                 = function(codecContext: PAVCodecContext;
    codec: PAVCodec; options: Pointer): Integer; cdecl;
  Tavcodec_free_context          = procedure(codecContext: PPAVCodecContext); cdecl;
  Tavcodec_send_packet           = function(codecContext: PAVCodecContext;
    packet: PAVPacket): Integer; cdecl;
  Tavcodec_receive_frame         = function(codecContext: PAVCodecContext;
    frame: PAVFrame): Integer; cdecl;
  Tavcodec_send_frame            = function(codecContext: PAVCodecContext;
    frame: PAVFrame): Integer; cdecl;
  Tavcodec_receive_packet        = function(codecContext: PAVCodecContext;
    packet: PAVPacket): Integer; cdecl;
  Tavcodec_flush_buffers         = procedure(codecContext: PAVCodecContext); cdecl;
  Tav_packet_alloc               = function: PAVPacket; cdecl;
  Tav_packet_free                = procedure(packet: PPAVPacket); cdecl;
  Tav_packet_unref               = procedure(packet: PAVPacket); cdecl;
  Tav_packet_rescale_ts          = procedure(packet: PAVPacket;
    tb_src, tb_dst: TAVRational); cdecl;
  Tav_packet_side_data_new       = function(psd: PPAVPacketSideData; pnb_sd: PInteger;
    side_data_type: Integer; size: NativeUInt; flags: Integer): PAVPacketSideData; cdecl;

  Tav_frame_alloc                = function: PAVFrame; cdecl;
  Tav_frame_free                 = procedure(frame: PPAVFrame); cdecl;
  Tav_frame_get_buffer           = function(frame: PAVFrame;
    align: Integer): Integer; cdecl;
  Tav_frame_make_writable        = function(frame: PAVFrame): Integer; cdecl;
  Tav_strerror                   = function(errnum: Integer; errbuf: PAnsiChar;
    errbuf_size: NativeUInt): Integer; cdecl;
  Tav_display_rotation_set       = procedure(matrix: PInteger; angle: Double); cdecl;
  Tav_get_sample_fmt_name        = function(sample_fmt: Integer): PAnsiChar; cdecl;
  Tav_get_pix_fmt                = function(name: PAnsiChar): Integer; cdecl;
  Tav_opt_set                    = function(obj: Pointer; name, val: PAnsiChar;
    search_flags: Integer): Integer; cdecl;

  Tsws_getContext                = function(srcW, srcH, srcFormat, dstW, dstH, dstFormat,
    flags: Integer; srcFilter, dstFilter, param: Pointer): PSwsContext; cdecl;
  Tsws_scale                     = function(context: PSwsContext; srcSlice, srcStride: Pointer;
    srcSliceY, srcSliceH: Integer; dst, dstStride: Pointer): Integer; cdecl;
  Tsws_freeContext               = procedure(context: PSwsContext); cdecl;

  Tav_channel_layout_default     = procedure(ch_layout: PAVChannelLayout;
    nb_channels: Integer); cdecl;
  Tav_channel_layout_copy        = function(dst: PAVChannelLayout;
    const src: PAVChannelLayout): Integer; cdecl;
  Tav_channel_layout_uninit      = procedure(ch_layout: PAVChannelLayout); cdecl;

  Tswr_alloc_set_opts2           = function(ps: PPSwrContext;
    const out_ch_layout: PAVChannelLayout; out_sample_fmt: Integer;
    out_sample_rate: Integer; const in_ch_layout: PAVChannelLayout;
    in_sample_fmt: Integer; in_sample_rate: Integer; log_offset: Integer;
    log_ctx: Pointer): Integer; cdecl;
  Tswr_init                      = function(s: PSwrContext): Integer; cdecl;
  Tswr_convert                   = function(s: PSwrContext; out_arg: Pointer;
    out_count: Integer; in_arg: Pointer; in_count: Integer): Integer; cdecl;
  Tswr_free                      = procedure(s: PPSwrContext); cdecl;

const
  AVMEDIA_TYPE_VIDEO          = 0;                    // FFmpegの映像stream種別
  AVMEDIA_TYPE_AUDIO          = 1;                    // FFmpegの音声stream種別
  AV_TIME_BASE                = 1000000;              // FFmpeg共通時間軸の1秒あたりtick数
  AVSEEK_FLAG_BACKWARD        = 1;                    // 指定位置以前のkeyframeへseekするflag
  AV_PIX_FMT_YUYV422          = 1;                    // YUY2/YUYV422のpixel format値
  AV_PIX_FMT_BGR24            = 3;                    // BGR24のpixel format値
  AV_PIX_FMT_YUV420P          = 0;                    // yuv420pのpixel format値
  AV_PIX_FMT_BGRA             = 28;                   // BGRAのpixel format値
  SWS_BILINEAR                = 2;                    // sws_scaleのbilinear変換flag
  AVIO_FLAG_WRITE             = 2;                    // avio_openで出力書き込みを指定するflag
  AV_CODEC_FLAG_GLOBAL_HEADER = 1 shl 22;             // codec headerをstream extradataへ出すflag
  AV_PKT_DATA_DISPLAYMATRIX   = 5;                    // 回転/反転などの表示行列side data
  AVERROR_EOF                 = -541478725;           // FFmpegのEOFエラー値
  AVERROR_EAGAIN              = -11;                  // FFmpegの再試行要求エラー値
  AV_NOPTS_VALUE              = -9223372036854775808; // PTS未設定を表すFFmpeg値
  AV_SAMPLE_FMT_S16           = 1;                    // signed 16bit PCMのsample format値
  AUDIO_OUTPUT_SAMPLE_RATE    = 48000;                // 既定の音声出力sample rate
  AUDIO_OUTPUT_CHANNELS       = 2;                    // 既定の音声出力channel数

type
  PAVCodecContextPublic = ^TAVCodecContextPublic;
  // avcodec_alloc_context3が確保する領域のprefix。未使用フィールドもsample_rateまでのABI位置を保つ。
  TAVCodecContextPublic = record
    av_class: Pointer; // FFmpeg内部クラス情報
    log_level_offset: Integer; // ログレベル補正
    codec_type: Integer; // 映像/音声などのメディア種別
    codec: PAVCodec; // FFmpeg所有のコーデック定義
    codec_id: Integer; // FFmpegのコーデックID
    codec_tag: Cardinal; // コンテナ側のコーデックタグ
    priv_data: Pointer; // FFmpeg内部用データ
    internal: Pointer; // FFmpeg内部状態
    opaque: Pointer; // FFmpeg内部用ポインタ
    bit_rate: Int64; // ビットレート
    flags: Integer; // パケットフラグ
    flags2: Integer; // 追加のcodec動作設定
    extradata: PByte; // デコーダ初期化用の追加データ
    extradata_size: Integer; // 追加データのバイト数
    time_base: TAVRational; // パケット時刻の時間単位
    pkt_timebase: TAVRational; // 入力packetの時間単位
    framerate: TAVRational; // ストリーム側のフレームレート
    delay: Integer; // codecの遅延フレーム数
    width: Integer; // 映像幅
    height: Integer; // 映像高さ
    coded_width: Integer; // 符号化された映像幅
    coded_height: Integer; // 符号化された映像高さ
    sample_aspect_ratio: TAVRational; // サンプルアスペクト比
    pix_fmt: Integer; // 画素形式。YUV420Pを指定
    sw_pix_fmt: Integer; // ソフトウェア転送時の画素形式
    color_primaries: Integer; // 色域
    color_trc: Integer; // 伝達特性
    colorspace: Integer; // 色変換の行列種別
    color_range: Integer; // 色範囲
    chroma_sample_location: Integer; // 色差のサンプル位置
    field_order: Integer; // フィールド順
    refs: Integer; // 参照フレーム数
    has_b_frames: Integer; // 並べ替えの遅延フレーム数
    slice_flags: Integer; // スライス処理設定
    draw_horiz_band: Pointer; // 帯状描画コールバック
    get_format: Pointer; // 画素形式選択コールバック
    max_b_frames: Integer; // Bフレーム数。逐次出力では0
    b_quant_factor: Single; // Bフレーム量子化係数
    b_quant_offset: Single; // Bフレーム量子化補正
    i_quant_factor: Single; // Iフレーム量子化係数
    i_quant_offset: Single; // Iフレーム量子化補正
    lumi_masking: Single; // 輝度による量子化補正
    temporal_cplx_masking: Single; // 時間複雑度による量子化補正
    spatial_cplx_masking: Single; // 空間複雑度による量子化補正
    p_masking: Single; // Pブロック量子化補正
    dark_masking: Single; // 暗部量子化補正
    nsse_weight: Integer; // ノイズ比較の重み
    me_cmp: Integer; // 動き探索の比較方式
    me_sub_cmp: Integer; // 小画素単位の動き比較方式
    mb_cmp: Integer; // マクロブロック比較方式
    ildct_cmp: Integer; // インターレースDCT比較方式
    dia_size: Integer; // 動き探索の探索範囲
    last_predictor_count: Integer; // 動き予測の候補数
    me_pre_cmp: Integer; // 事前の動き探索比較方式
    pre_dia_size: Integer; // 事前探索の探索範囲
    me_subpel_quality: Integer; // 小画素探索の品質
    me_range: Integer; // 動きベクトルの最大範囲
    mb_decision: Integer; // マクロブロックの選択方式
    intra_matrix: Pointer; // フレーム内量子化行列
    inter_matrix: Pointer; // フレーム間量子化行列
    chroma_intra_matrix: Pointer; // 色差のフレーム内量子化行列
    intra_dc_precision: Integer; // 8.1.1ではFF_API_INTRA_DC_PRECISION有効で存在するABIフィールド
    mb_lmin: Integer; // マクロブロックの最小量子化値
    mb_lmax: Integer; // マクロブロックの最大量子化値
    bidir_refine: Integer; // 双方向予測の精度
    keyint_min: Integer; // キーフレーム間隔の下限
    gop_size: Integer; // キーフレーム間隔
    mv0_threshold: Integer; // ゼロ動きベクトルの閾値
    slices: Integer; // スライス数
    sample_rate: Integer; // 音声サンプルレート
    sample_fmt: Integer; // 音声サンプル形式。AACはplanar float
    ch_layout: TAVChannelLayout; // 音声チャンネルレイアウト
    frame_size: Integer; // 音声フレームサイズ
  end;

  PAVFrameAudioPublic = ^TAVFrameAudioPublic;
  // av_frame_allocが確保する領域。音声のsample_rate/ch_layoutへのアクセス用に中間フィールドを保持。
  TAVFrameAudioPublic = record
    data: array[0..7] of PByte; // フレームデータのプレーンポインタ
    linesize: array[0..7] of Integer; // 各プレーンの1行バイト数
    extended_data: Pointer; // 音声などで使う拡張プレーン
    width: Integer; // 映像幅
    height: Integer; // 映像高さ
    nb_samples: Integer; // 音声サンプル数
    format: Integer; // ピクセル形式またはサンプル形式
    pict_type: Integer; // 映像フレーム種別
    sample_aspect_ratio: TAVRational; // サンプルアスペクト比
    pts: Int64; // フレームの表示時刻
    pkt_dts: Int64; // packetのデコード時刻
    time_base: TAVRational; // パケット時刻の時間単位
    quality: Integer; // フレーム単位の品質
    opaque: Pointer; // FFmpeg内部用ポインタ
    repeat_pict: Integer; // 追加表示するフィールド数
    sample_rate: Integer; // 音声サンプルレート
    buf: array[0..7] of Pointer; // FFmpeg所有のプレーンバッファ参照
    extended_buf: Pointer; // 追加プレーンのバッファ参照
    nb_extended_buf: Integer; // 追加バッファ数
    side_data: Pointer; // サイドデータ
    nb_side_data: Integer; // フレーム付加情報の数
    flags: Integer; // パケットフラグ
    color_range: Integer; // 色範囲
    color_primaries: Integer; // 色域
    color_trc: Integer; // 伝達特性
    colorspace: Integer; // 色変換の行列種別
    chroma_location: Integer; // クロマ位置
    best_effort_timestamp: Int64; // デコーダが推定する表示時刻
    metadata: Pointer; // メタデータ
    decode_error_flags: Integer; // 復号エラーの種類
    hw_frames_ctx: Pointer; // ハードウェアフレームの所有参照
    opaque_ref: Pointer; // FFmpeg内部用参照
    crop_top: NativeUInt; // 上端から除外する行数
    crop_bottom: NativeUInt; // 下端から除外する行数
    crop_left: NativeUInt; // 左端から除外する列数
    crop_right: NativeUInt; // 右端から除外する列数
    private_ref: Pointer; // FFmpeg内部の所有参照
    ch_layout: TAVChannelLayout; // 音声チャンネルレイアウト
    duration: Int64; // パケットの長さ
    alpha_mode: Integer; // アルファチャンネルの表現方式
  end;

  Tav_opt_set_int = function(obj: Pointer; name: PAnsiChar; val: Int64;
    search_flags: Integer): Integer; cdecl;
  Tav_opt_set_sample_fmt = function(obj: Pointer; name: PAnsiChar;
    sample_fmt: Integer; search_flags: Integer): Integer; cdecl;
  Tav_opt_set_chlayout = function(obj: Pointer; name: PAnsiChar;
    const layout: PAVChannelLayout; search_flags: Integer): Integer; cdecl;


implementation
end.
