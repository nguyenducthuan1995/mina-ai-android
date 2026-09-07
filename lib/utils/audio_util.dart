import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter_pcm_player/flutter_pcm_player.dart';

/// 音频工具类，用于处理Opus音频编解码和录制播放
class AudioUtil {
  static const String TAG = "AudioUtil";
  static const int SAMPLE_RATE = 16000;
  static const int CHANNELS = 1;
  static const int FRAME_DURATION = 60; // 毫秒
  static const int SAMPLES_PER_FRAME = (SAMPLE_RATE * FRAME_DURATION) ~/ 1000; // 960 samples
  static const int BYTES_PER_FRAME = SAMPLES_PER_FRAME * 2; // 1920 bytes
  static final List<int> _pcmBuffer = [];

  static final AudioRecorder _audioRecorder = AudioRecorder();
  static ja.AudioPlayer? _player;
  static bool _isRecorderInitialized = false;
  static bool _isPlayerInitialized = false;
  static bool _isRecording = false;
  static bool _isPlaying = false;
  static final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();
  static String? _tempFilePath;
  static Timer? _audioProcessingTimer;

  // Opus相关
  static final _encoder = SimpleOpusEncoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
    application: Application.voip,
  );
  static final _decoder = SimpleOpusDecoder(
    sampleRate: SAMPLE_RATE,
    channels: CHANNELS,
  );

  // FlutterPcmPlayer实例
  static FlutterPcmPlayer? _pcmPlayer;

  /// 获取音频流
  static Stream<Uint8List> get audioStream => _audioStreamController.stream;

  /// 初始化音频录制器
  static Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;

    print('$TAG: 开始初始化录音器');

    // Chỉ yêu cầu quyền Microphone, không yêu cầu các quyền lưu trữ/bluetooth không cần thiết
    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      print('$TAG: Quyền microphone bị từ chối');
      throw Exception('Cần quyền microphone để thu âm');
    }

    // 检查是否可用
    print('$TAG: 检查PCM16编码是否支持');
    final isAvailable = await _audioRecorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    print('$TAG: PCM16编码支持状态: $isAvailable');

    // 设置音频模式 - 参考Android原生实现
    print('$TAG: 配置音频会话');
    final session = await AudioSession.instance;

    // 使用与原生Android实现更接近的配置
    if (Platform.isAndroid) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientExclusive,
          androidWillPauseWhenDucked: false,
        ),
      );
    } else {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
        ),
      );
      await session.setActive(true);
    }

    _isRecorderInitialized = true;
    print('$TAG: 录音器初始化成功');
  }

  /// 初始化音频播放器
  static Future<void> initPlayer() async {
    // 确保任何旧播放器被释放
    await stopPlaying();

    try {
      print('$TAG: 使用简单方式初始化PCM播放器');

      // 创建新的播放器实例 - 完全按照官方示例的简单方式
      _pcmPlayer = FlutterPcmPlayer();
      await _pcmPlayer!.initialize();
      await _pcmPlayer!.play();

      _isPlayerInitialized = true;
      print('$TAG: PCM播放器初始化成功');
    } catch (e) {
      print('$TAG: PCM播放器初始化失败: $e');
      _isPlayerInitialized = false;
    }
  }

  /// 播放Opus音频数据
  static Future<void> playOpusData(Uint8List opusData) async {
    try {
      // 如果播放器未初始化，先初始化
      if (!_isPlayerInitialized || _pcmPlayer == null) {
        await initPlayer();
      }

      // 解码Opus数据
      final Int16List pcmData = _decoder.decode(input: opusData);

      // 准备PCM数据（按照示例直接方式）
      final Uint8List pcmBytes = Uint8List(pcmData.length * 2);
      ByteData bytes = ByteData.view(pcmBytes.buffer);

      // 使用小端字节序
      for (int i = 0; i < pcmData.length; i++) {
        bytes.setInt16(i * 2, pcmData[i], Endian.little);
      }

      // 直接发送到播放器
      if (_pcmPlayer != null) {
        await _pcmPlayer!.feed(pcmBytes);
      }
    } catch (e) {
      print('$TAG: 播放失败: $e');

      // 简单重置并重新初始化
      await stopPlaying();
      await initPlayer();
    }
  }

  /// 停止播放
  static Future<void> stopPlaying() async {
    if (_pcmPlayer != null) {
      try {
        await _pcmPlayer!.stop();
        print('$TAG: 播放器已停止');
      } catch (e) {
        print('$TAG: 停止播放失败: $e');
      }
      _pcmPlayer = null;
      _isPlayerInitialized = false;
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    _audioStreamController.close();
    print('$TAG: 资源已释放');
  }

  /// 开始录音
  static Future<void> startRecording() async {
    if (!_isRecorderInitialized) {
      await initRecorder();
    }

    if (_isRecording) return;

    try {
      print('$TAG: 尝试启动录音');

      // 确保麦克风权限已获取 - 使用不同方式检查权限
      final status = await Permission.microphone.status;
      print('$TAG: 麦克风权限状态: $status');

      if (status != PermissionStatus.granted) {
        final result = await Permission.microphone.request();
        print('$TAG: 请求麦克风权限结果: $result');
        if (result != PermissionStatus.granted) {
          print('$TAG: 麦克风权限被拒绝');
          return;
        }
      }

      // 尝试直接使用音频流
      try {
        print('$TAG: 尝试启动流式录音');
        _pcmBuffer.clear();
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: SAMPLE_RATE,
            numChannels: CHANNELS,
          ),
        );

        _isRecording = true;
        print('$TAG: 流式录音启动成功');

        // 直接从流中处理数据，使用累加缓冲区确保每帧恰好 60ms (960 采样 / 1920 字节)
        stream.listen(
          (data) async {
            if (data.isNotEmpty) {
              _pcmBuffer.addAll(data);
              while (_pcmBuffer.length >= BYTES_PER_FRAME) {
                final frameBytes = Uint8List.fromList(
                  _pcmBuffer.sublist(0, BYTES_PER_FRAME),
                );
                _pcmBuffer.removeRange(0, BYTES_PER_FRAME);

                try {
                  final Int16List pcmInt16 = frameBytes.buffer.asInt16List(
                    frameBytes.offsetInBytes,
                    SAMPLES_PER_FRAME,
                  );
                  final opusData = Uint8List.fromList(
                    _encoder.encode(input: pcmInt16),
                  );
                  _audioStreamController.add(opusData);
                } catch (e) {
                  print('$TAG: Opus编码失败: $e');
                }
              }
            }
          },
          onError: (error) {
            print('$TAG: 音频流错误: $error');
            _isRecording = false;
          },
          onDone: () {
            print('$TAG: 音频流结束');
            _isRecording = false;
          },
        );
      } catch (e) {
        print('$TAG: 流式录音失败: $e');
        _isRecording = false;
        rethrow;
      }
    } catch (e, stackTrace) {
      print('$TAG: 启动录音失败: $e');
      print(stackTrace);
      _isRecording = false;
    }
  }

  /// 停止录音
  static Future<String?> stopRecording() async {
    if (!_isRecorderInitialized || !_isRecording) return null;

    // 取消定时器
    _audioProcessingTimer?.cancel();

    // 如果缓冲区还有残留音频，填充至1920字节后发出最后一帧
    if (_pcmBuffer.isNotEmpty) {
      while (_pcmBuffer.length < BYTES_PER_FRAME) {
        _pcmBuffer.add(0);
      }
      try {
        final frameBytes = Uint8List.fromList(
          _pcmBuffer.sublist(0, BYTES_PER_FRAME),
        );
        _pcmBuffer.clear();
        final Int16List pcmInt16 = frameBytes.buffer.asInt16List(
          frameBytes.offsetInBytes,
          SAMPLES_PER_FRAME,
        );
        final opusData = Uint8List.fromList(
          _encoder.encode(input: pcmInt16),
        );
        _audioStreamController.add(opusData);
      } catch (e) {
        print('$TAG: 编码末尾音频帧失败: $e');
      }
    }
    _pcmBuffer.clear();

    // 停止录音
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      print('$TAG: 停止录音: $path');
      return path;
    } catch (e) {
      print('$TAG: 停止录音失败: $e');
      _isRecording = false;
      return null;
    }
  }

  /// 检查是否正在录音
  static bool get isRecording => _isRecording;

  /// 检查是否正在播放
  static bool get isPlaying => _isPlaying;
}
