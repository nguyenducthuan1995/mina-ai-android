import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/assistant_persona.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/automotive_tool_service.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../widgets/automotive_map_view.dart';
import 'dart:async';
import 'dart:io';


class VoiceCallScreen extends StatefulWidget {
  final Conversation conversation;
  final XiaozhiConfig xiaozhiConfig;

  const VoiceCallScreen({
    super.key,
    required this.conversation,
    required this.xiaozhiConfig,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late XiaozhiService _xiaozhiService;
  bool _isConnected = false;
  bool _isSpeaking = false;
  bool _isAiSpeaking = false;
  String _statusText = 'Đang kết nối...';
  String _currentSubtitle = 'Chào bạn! Tôi là Mina AI, bạn muốn trò chuyện gì nào?';
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;
  bool _serverReady = false;
  bool _isManualExit = false;

  // Android STT (tiếng Việt) — thay thế audio PCM gửi lên server
  final SpeechToText _stt = SpeechToText();
  bool _speechEnabled = false;   // STT đã init thành công
  bool _sttListening = false;    // Đang lắng nghe qua Android STT

  // Biến tích lũy câu nói và bộ đếm chờ nói xong (tránh ngắt câu giữa chừng khi nói cả câu dài)
  String _accumulatedSentence = '';
  Timer? _sentenceDebounceTimer;


  late AnimationController _animationController;
  final List<double> _audioLevels = List.filled(24, 0.08);
  Timer? _audioVisualizerTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _xiaozhiService = XiaozhiService(
      websocketUrl: widget.xiaozhiConfig.websocketUrl,
      macAddress: widget.xiaozhiConfig.macAddress,
      token: widget.xiaozhiConfig.token,
    );

    _xiaozhiService.setMessageListener(_handleServerMessage);
    _xiaozhiService.addListener(_handleServiceEvent);

    final persona = AssistantPersona.findById(widget.conversation.personaId);
    if (persona != null) {
      _currentSubtitle = persona.greetingMessage;
    }

    _connectToVoiceService();
    _startAudioVisualizer();
    _initStt(); // Khởi tạo Android STT tiếng Việt
  }

  void _handleServiceEvent(XiaozhiServiceEvent event) {
    if (!mounted) return;
    if (event.type == XiaozhiServiceEventType.disconnected) {
      print('VoiceCall: Nhận sự kiện mất kết nối');
      if (!_isManualExit) {
        setState(() {
          _isConnected = false;
          _isSpeaking = false;
          _isAiSpeaking = false;
          _statusText = 'Mất kết nối • Đang thử lại...';
        });

        // Tự động thử kết nối lại sau 2 giây
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted && !_isConnected && !_isManualExit) {
            _connectToVoiceService();
          }
        });
      }
    } else if (event.type == XiaozhiServiceEventType.connected) {
      setState(() {
        _isConnected = true;
      });
    }
  }

  void _handleServerMessage(dynamic message) {
    if (!mounted) return;
    if (message is Map<String, dynamic>) {
      final type = message['type'] ?? '';

      if (type == 'hello') {
        print('VoiceCall: Đã nhận hello từ server: $message');
        setState(() {
          _serverReady = true;
          _isConnected = true;
          _statusText = 'Đang lắng nghe...';
        });

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isConnected && !_isSpeaking) {
            _startVietnameseStt();
          }
        });
      } else if (type == 'tts') {
        final state = message['state'] ?? '';
        final text = message['text'] ?? '';
        if (state == 'start') {
          // AI bắt đầu nói → dừng timer debounce, reset câu đang nói, dừng STT
          _sentenceDebounceTimer?.cancel();
          _accumulatedSentence = '';
          _stt.stop();
          _sttListening = false;
          setState(() {
            _isAiSpeaking = true;
            _isSpeaking = false;
            _statusText = 'Mina AI đang nói...';
          });
        } else if (state == 'sentence_start' && text.isNotEmpty) {
          setState(() {
            _currentSubtitle = text;
            _isAiSpeaking = true;
            _isSpeaking = false;
            _statusText = 'Mina AI đang nói...';
          });
        } else if (state == 'stop') {
          setState(() {
            _isAiSpeaking = false;
            _isSpeaking = false;
            _statusText = '🎤 Đang lắng nghe tiếng Việt...';
          });
          // AI nói xong → restart Android STT để nghe tiếp
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _isConnected && !_isAiSpeaking && !_isManualExit) {
              _startVietnameseStt();
            }
          });
        }
      } else if (type == 'stt') {
        final text = message['text'] ?? '';
        if (text.isNotEmpty) {
          final lower = text.toLowerCase();
          final isNav = lower.contains('dẫn đường') ||
              lower.contains('chỉ đường') ||
              lower.contains('bản đồ') ||
              lower.contains('google map') ||
              lower.contains('tìm đường') ||
              lower.contains('cây xăng') ||
              lower.contains('trạm xăng') ||
              lower.contains('đi đến') ||
              lower.contains('đi tới');
          setState(() {
            _currentSubtitle = isNav
                ? 'Bạn: $text\n🚗 Đang mở Google Maps dẫn đường...'
                : 'Bạn: $text';
            _statusText =
                isNav ? 'Đang mở Google Maps...' : 'Mina AI đang suy nghĩ...';
            _isSpeaking = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _isManualExit = true;
    _callTimer?.cancel();
    _sentenceDebounceTimer?.cancel();
    _audioVisualizerTimer?.cancel();
    _animationController.dispose();
    _stt.cancel(); // Dừng Android STT
    _xiaozhiService.removeListener(_handleServiceEvent);
    _xiaozhiService.setMessageListener(null);
    _xiaozhiService.disconnectVoiceCall();
    super.dispose();
  }

  void _connectToVoiceService() async {
    setState(() {
      _statusText = 'Đang kết nối...';
      _isConnected = false;
    });

    // Lấy system prompt của persona hiện tại để gửi lên server
    final persona = AssistantPersona.findById(widget.conversation.personaId);
    final systemPrompt = persona?.systemPrompt;

    try {
      final success = await _xiaozhiService.connectVoiceCall(
        systemPrompt: systemPrompt,
      );
      if (!mounted) return;

      if (success) {
        setState(() {
          _statusText = 'Đã kết nối';
          _isConnected = true;
          _serverReady = true;
        });

        if (mounted) {
          _showCustomSnackbar(
            message: 'Đã kết nối trợ lý giọng nói xe hơi',
            icon: Icons.check_circle,
            iconColor: Colors.greenAccent,
          );
        }

        _startCallTimer();

        Provider.of<ConversationProvider>(context, listen: false).addMessage(
          conversationId: widget.conversation.id,
          role: MessageRole.assistant,
          content: 'Cuộc trò chuyện Mina AI bắt đầu',
        );

        // Kích hoạt Micro lắng nghe sau khi kết nối hoàn tất
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isConnected && !_isSpeaking && !_isAiSpeaking) {
            _startVietnameseStt();
          }
        });
      } else {
        setState(() {
          _statusText = 'Kết nối thất bại';
          _isConnected = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Kết nối thất bại';
          _isConnected = false;
        });
        print('VoiceCall: Kết nối thất bại: $e');

        _showCustomSnackbar(
          message: 'Không thể kết nối: $e',
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = Duration(seconds: timer.tick);
        });
      }
    });
  }

  void _startAudioVisualizer() {
    _audioVisualizerTimer?.cancel();
    _audioVisualizerTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_isConnected && mounted) {
        setState(() {
          for (int i = 0; i < _audioLevels.length - 1; i++) {
            _audioLevels[i] = _audioLevels[i + 1];
          }

          if (_isAiSpeaking) {
            _audioLevels[_audioLevels.length - 1] =
                0.15 + (0.75 * (0.4 + 0.6 * _animationController.value));
          } else if (_isSpeaking) {
            _audioLevels[_audioLevels.length - 1] =
                0.1 + (0.6 * (0.3 + 0.7 * _animationController.value));
          } else {
            _audioLevels[_audioLevels.length - 1] =
                0.05 + (0.12 * (0.5 + 0.5 * _animationController.value));
          }
        });
      }
    });
  }

  // Android STT locale cache (set trong _initStt) + last partial result cache
  String _sttLocale = 'vi_VN';
  String _lastPartialResult = ''; // Fallback khi final result rỗng

  /// Khởi tạo Android SpeechRecognizer — chỉ chạy 1 lần khi màn hình mở
  Future<void> _initStt() async {
    try {
      _speechEnabled = await _stt.initialize(
        onError: (error) {
          print('VoiceCall STT Error: ${error.errorMsg}');
          _sttListening = false;
        },
        onStatus: (status) {
          print('VoiceCall STT Status: $status');
          if (status == 'done' || status == 'notListening') {
            _sttListening = false;
          }
        },
      );

      if (_speechEnabled) {
        // Cache locale vi tốt nhất (chỉ check 1 lần khi init, tránh slow per-call check)
        final locales = await _stt.locales();
        final viLocale = locales.where((l) => l.localeId.startsWith('vi')).firstOrNull;
        if (viLocale != null) {
          _sttLocale = viLocale.localeId;
          print('VoiceCall: STT vi locale: $_sttLocale');
        } else {
          _sttLocale = 'vi_VN'; // Thử trực tiếp dù không có trong list
          print('VoiceCall: vi locale không có trong list, thử vi_VN trực tiếp');
        }
      }
      print('VoiceCall: STT init: $_speechEnabled, locale: $_sttLocale');
    } catch (e) {
      print('VoiceCall: STT init thất bại: $e');
      _speechEnabled = false;
    }
  }

  /// Lên lịch gửi câu hoàn chỉnh sau khi người dùng thực sự im lặng 2.2 giây
  void _scheduleSentenceSend() {
    _sentenceDebounceTimer?.cancel();
    _sentenceDebounceTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || !_isConnected || _isAiSpeaking || _isManualExit) return;
      final fullText = _accumulatedSentence.trim();
      _accumulatedSentence = '';

      if (fullText.isEmpty) return;

      print('VoiceCall STT: [Gửi trọn vẹn cả câu] "$fullText"');
      _sttListening = false;
      _stt.stop();

      // Gửi toàn bộ câu nói hoàn chỉnh lên server (bypass Chinese ASR)
      _xiaozhiService.sendVoiceTextInput(fullText);

      if (mounted) {
        final lower = fullText.toLowerCase();
        final isNav = lower.contains('dẫn đường') ||
            lower.contains('chỉ đường') ||
            lower.contains('bản đồ') ||
            lower.contains('tìm đường') ||
            lower.contains('đi đến') ||
            lower.contains('đi tới');
        setState(() {
          _currentSubtitle = isNav
              ? 'Bạn: $fullText\n🚗 Đang mở Google Maps...'
              : 'Bạn: $fullText';
          _statusText = 'Mina AI đang suy nghĩ...';
          _isSpeaking = false;
        });
      }
    });
  }

  /// Bắt đầu lắng nghe tiếng Việt qua Android SpeechRecognizer
  /// Tích lũy các chặng nói và dùng debounce 2.2s để gom đủ cả câu 10 từ
  void _startVietnameseStt() async {
    if (!mounted || !_isConnected || _isAiSpeaking || _sttListening || _isManualExit) return;

    if (!_speechEnabled) {
      print('VoiceCall: STT không khả dụng, dùng audio fallback');
      _startSpeakingFallback();
      return;
    }

    setState(() {
      _isSpeaking = true;
      _sttListening = true;
      _statusText = '🎤 Đang lắng nghe tiếng Việt...';
    });

    _stt
        .listen(
          onResult: (result) {
            if (!mounted) return;
            final text = result.recognizedWords.trim();

            if (!result.finalResult) {
              // Partial result: hiển thị câu đang nói real-time
              if (text.isNotEmpty) {
                _lastPartialResult = text;
                final preview = _accumulatedSentence.isEmpty
                    ? text
                    : '$_accumulatedSentence $text';
                setState(() => _currentSubtitle = 'Bạn: $preview...');
                // Reset timer nếu người dùng vẫn đang tiếp tục nói
                _sentenceDebounceTimer?.cancel();
              }
              return;
            }

            // Khi một chặng nhận diện hoàn tất (người dùng ngắt hơi ngắn)
            final segmentText = text.isNotEmpty ? text : _lastPartialResult;
            _lastPartialResult = '';

            if (segmentText.isNotEmpty) {
              if (_accumulatedSentence.isEmpty) {
                _accumulatedSentence = segmentText;
              } else {
                // Chỉ bỏ qua nếu segment mới hoàn toàn giống hệt câu đã tích lũy
                // (do SpeechRecognizer gửi lại kết quả trùng lặp)
                // Còn lại luôn nối thêm để không nuốt chữ lặp hợp lệ
                if (segmentText != _accumulatedSentence &&
                    !_accumulatedSentence.endsWith(segmentText)) {
                  _accumulatedSentence = '$_accumulatedSentence $segmentText';
                }
              }
              setState(() => _currentSubtitle = 'Bạn: $_accumulatedSentence');
            }

            // Bắt đầu đếm ngược 2.2s để chờ xem người dùng có nói thêm từ nào nữa không
            if (_accumulatedSentence.isNotEmpty) {
              _scheduleSentenceSend();
            }
          },
          localeId: _sttLocale,
          cancelOnError: false,
          partialResults: true,
          pauseFor: const Duration(seconds: 4),   // 4s im lặng trước khi SpeechRecognizer tự ngắt
          listenFor: const Duration(seconds: 90), // max 90s/phiên
          onSoundLevelChange: (level) {
            if (mounted && _isSpeaking) {
              final normalizedLevel = (level / 10.0).clamp(0.05, 0.95);
              setState(() {
                for (int i = 0; i < _audioLevels.length - 1; i++) {
                  _audioLevels[i] = _audioLevels[i + 1];
                }
                _audioLevels[_audioLevels.length - 1] = normalizedLevel;
              });
            }
          },
        )
        .then((_) {
          _sttListening = false;
          // Nếu timer debounce vẫn đang đếm ngược (người dùng có thể còn nói tiếp câu):
          // Lập tức khởi động lại STT để bắt các từ tiếp theo không bị ngắt quãng!
          if (_sentenceDebounceTimer != null && _sentenceDebounceTimer!.isActive) {
            if (mounted && _isConnected && !_isAiSpeaking && !_isManualExit) {
              _startVietnameseStt();
            }
          } else {
            // Không có câu dở dang -> khởi động lại bình thường sau 300ms
            if (mounted && _isConnected && !_isAiSpeaking && !_isManualExit) {
              setState(() {
                _isSpeaking = false;
                _statusText = '🎤 Đang lắng nghe tiếng Việt...';
              });
              Future.delayed(const Duration(milliseconds: 300), _startVietnameseStt);
            }
          }
        });
  }

  /// Fallback: audio streaming cũ (dùng khi không có STT vi-VN)
  void _startSpeakingFallback() {
    if (!_isSpeaking) {
      setState(() {
        _isSpeaking = true;
        _statusText = 'Đang lắng nghe...';
      });

      _xiaozhiService
          .startListeningCall()
          .then((_) {
            if (mounted) print('VoiceCall: Đã bắt đầu thu âm (fallback mode)');
          })
          .catchError((e) {
            print('VoiceCall: Thu âm thất bại: $e');
            if (mounted) setState(() => _isSpeaking = false);
          });
    }
  }

  void _sendAbortMessage() {
    // Hủy mọi debounce đang đếm ngược và xóa câu đang tích lũy
    _sentenceDebounceTimer?.cancel();
    _accumulatedSentence = '';
    _lastPartialResult = '';

    _xiaozhiService.sendAbortMessage();
    setState(() {
      _isAiSpeaking = false;
      _isSpeaking = false;
      _statusText = 'Đã ngắt lời';
    });

    if (mounted) {
      _showCustomSnackbar(
        message: 'Đã ngắt lời Mina AI',
        icon: Icons.pan_tool,
        iconColor: Colors.orangeAccent,
      );
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _startVietnameseStt();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;

    return PopScope(
      canPop: _isManualExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isManualExit) {
          print('VoiceCall: Đã chặn cử chỉ back hoặc nút back ngoài ý muốn');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: (isLandscape && isCarMode)
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: Container(
                margin: const EdgeInsets.only(left: 12, top: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  onPressed: () {
                    _isManualExit = true;
                    _xiaozhiService.stopPlayback();
                    _xiaozhiService.disconnectVoiceCall();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF0B1120),
        ),
        child: (isLandscape && isCarMode)
            ? _buildLandscapeCarLayout()
            : SafeArea(
                child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
              ),
      ),
    ),
  );
}

  bool get isCarMode =>
      widget.conversation.personaId == 'mina_car' ||
      widget.conversation.title.toLowerCase().contains('lái xe') ||
      widget.conversation.id.contains('car');

  /// Giao diện chế độ Xe Hơi Landscape (Giống Lily AI): Bản đồ tràn viền 100% bên phải, sidebar gọn gàng bên trái
  Widget _buildLandscapeCarLayout() {
    final screenWidth = MediaQuery.of(context).size.width;
    // Sidebar chiếm ~28% bề ngang màn hình (tối thiểu 240px, tối đa 310px)
    final sidebarWidth = (screenWidth * 0.28).clamp(240.0, 310.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- CỘT TRÁI: MINA AI SIDEBAR (28% bề ngang) ---
        SizedBox(
          width: sidebarWidth,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1.5,
                ),
              ),
            ),
            child: SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  children: [
                    // Header gồm nút Back tròn tinh tế và Tên trợ lý
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                            onPressed: () {
                              _isManualExit = true;
                              _xiaozhiService.stopPlayback();
                              _xiaozhiService.disconnectVoiceCall();
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.conversation.title.isEmpty ? 'Mina Lái Xe' : widget.conversation.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Thân cuộn mượt
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _buildAvatar(size: 48),
                            const SizedBox(height: 4),
                            _buildStatusBadge(),
                            const SizedBox(height: 6),
                            _buildSubtitleCard(),
                            const SizedBox(height: 6),
                            _buildAudioVisualizer(height: 24),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),
                    // Hàng nút điều khiển ở đáy sidebar
                    _buildControlButtonsRow(),
                  ],
                ),
              ),
            ),
          ),
        ),

        // --- CỘT PHẢI: BẢN ĐỒ DẪN ĐƯỜNG TRÀN VIỀN 100% (72% BỀ NGANG, SÁT MÉP TRÊN/DƯỚI/PHẢI) ---
        Expanded(
          child: AutomotiveMapView(
            onOpenExternalMaps: () {
              _showCustomSnackbar(
                message: 'Đang mở Google Maps dẫn đường...',
                icon: Icons.navigation_rounded,
                iconColor: Colors.blueAccent,
              );
            },
            onSelectPoi: (dest) {
              _showCustomSnackbar(
                message: 'Đang dẫn đường tới $dest...',
                icon: Icons.navigation_rounded,
                iconColor: Colors.greenAccent,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    // CarMode sử dụng _buildLandscapeCarLayout() — được gọi trực tiếp từ build()
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAvatar(size: 90),
                const SizedBox(height: 8),
                Text(
                  widget.conversation.title.isEmpty ? 'Mina AI' : widget.conversation.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                _buildStatusBadge(),
                const SizedBox(height: 6),
                Text(
                  'Thời gian: ${_formatDuration(_callDuration)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSubtitleCard(),
                const SizedBox(height: 10),
                _buildAudioVisualizer(height: 56),
                const SizedBox(height: 14),
                _buildControlButtonsRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    if (isCarMode) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              SizedBox(
                height: 240,
                width: double.infinity,
                child: AutomotiveMapView(
                  onOpenExternalMaps: () {
                    _showCustomSnackbar(
                      message: 'Đang mở Google Maps dẫn đường...',
                      icon: Icons.navigation_rounded,
                      iconColor: Colors.blueAccent,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _buildAvatar(size: 70),
              const SizedBox(height: 6),
              Text(
                widget.conversation.title.isEmpty
                    ? 'Mina Lái Xe'
                    : widget.conversation.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusBadge(),
              const SizedBox(height: 8),
              _buildSubtitleCard(),
              const SizedBox(height: 8),
              _buildAudioVisualizer(height: 45),
              const SizedBox(height: 16),
              _buildControlButtonsRow(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            _buildAvatar(size: 120),
            const SizedBox(height: 16),
            Text(
              widget.conversation.title.isEmpty ? 'Mina AI' : widget.conversation.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _buildStatusBadge(),
            const SizedBox(height: 8),
            Text(
              'Thời gian: ${_formatDuration(_callDuration)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            _buildSubtitleCard(),
            const SizedBox(height: 20),
            _buildAudioVisualizer(height: 80),
            const SizedBox(height: 32),
            _buildControlButtonsRow(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({required double size}) {
    final persona =
        widget.conversation.personaId.isNotEmpty
            ? AssistantPersona.findById(widget.conversation.personaId)
            : null;

    final glowColor =
        _isAiSpeaking
            ? (persona?.iconColor ?? const Color(0xFF38BDF8))
            : (_isConnected ? const Color(0xFF10B981) : Colors.redAccent);

    return GestureDetector(
      onTap: () {
        if (!_isConnected) {
          _connectToVoiceService();
        } else if (_isAiSpeaking) {
          _sendAbortMessage();
        } else if (!_isSpeaking) {
          _startVietnameseStt();
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              persona?.iconColor ?? const Color(0xFF38BDF8),
              const Color(0xFF6366F1),
              const Color(0xFFEC4899),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.4),
              blurRadius: _isAiSpeaking ? 25 : 14,
              spreadRadius: _isAiSpeaking ? 4 : 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CircleAvatar(
            backgroundColor: const Color(0xFF1E293B),
            child: Icon(
              persona?.icon ?? Icons.smart_toy_rounded,
              color: persona?.iconColor ?? const Color(0xFF38BDF8),
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isWorking = _isConnected;
    final text = _isAiSpeaking
        ? 'Mina AI đang nói... (Chạm để ngắt lời)'
        : (_isConnected ? _statusText : _statusText);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!_isConnected) {
            _connectToVoiceService();
          } else if (_isAiSpeaking) {
            _sendAbortMessage();
          } else if (!_isSpeaking) {
            _startVietnameseStt();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isWorking
                ? const Color(0xFF10B981).withOpacity(0.2)
                : Colors.red.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isWorking
                  ? Colors.greenAccent.withOpacity(0.5)
                  : Colors.redAccent.withOpacity(0.6),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isWorking ? Colors.greenAccent : Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color: (isWorking ? Colors.greenAccent : Colors.redAccent)
                          .withOpacity(0.6),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: isWorking ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 52, maxHeight: 85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Text(
            _currentSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioVisualizer({required double height}) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _audioLevels.length,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            width: 4,
            height: (height - 12) * _audioLevels[index],
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: _isAiSpeaking
                    ? [const Color(0xFF06B6D4), const Color(0xFF3B82F6)]
                    : [const Color(0xFF10B981), const Color(0xFF34D399)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtonsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          icon: Icons.call_end_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFFEF4444),
          label: 'Kết thúc',
          size: 52,
          onPressed: () async {
            _isManualExit = true;
            await _xiaozhiService.sendAbortMessage();
            if (mounted) Navigator.pop(context);
          },
        ),
        const SizedBox(width: 18),
        if (!_isConnected)
          _buildActionButton(
            icon: Icons.refresh_rounded,
            color: Colors.white,
            backgroundColor: const Color(0xFF10B981),
            label: 'Kết nối lại',
            size: 56,
            onPressed: _connectToVoiceService,
          )
        else
          _buildActionButton(
            icon: _isSpeaking ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: Colors.white,
            backgroundColor: _isSpeaking ? const Color(0xFF10B981) : const Color(0xFF64748B),
            label: _isSpeaking ? 'Đang nghe' : 'Tạm dừng',
            size: 56,
            onPressed: () {
              if (_isSpeaking) {
                _xiaozhiService.stopListeningCall();
                setState(() {
                  _isSpeaking = false;
                  _statusText = 'Tạm dừng (Chạm để nghe)';
                });
              } else {
                _startVietnameseStt();
              }
            },
          ),
        const SizedBox(width: 18),
        _buildActionButton(
          icon: Icons.pan_tool_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFFF59E0B),
          label: 'Ngắt lời',
          size: 52,
          onPressed: _sendAbortMessage,
        ),
        const SizedBox(width: 18),
        _buildActionButton(
          icon: Icons.navigation_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFF2563EB),
          label: 'Bản đồ',
          size: 52,
          onPressed: () {
            AutomotiveToolService.instance.openNavigation('');
            _showCustomSnackbar(
              message: 'Đang mở Google Maps dẫn đường...',
              icon: Icons.navigation_rounded,
              iconColor: Colors.blueAccent,
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required String label,
    required double size,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(child: Icon(icon, color: color, size: size * 0.45)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showCustomSnackbar({
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1E293B),
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
