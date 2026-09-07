import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/models/assistant_persona.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
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
            _startSpeaking();
          }
        });
      } else if (type == 'tts') {
        final state = message['state'] ?? '';
        final text = message['text'] ?? '';
        if (state == 'start') {
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
            _isSpeaking = true;
            _statusText = 'Đang lắng nghe liên tục...';
          });
        }
      } else if (type == 'stt') {
        final text = message['text'] ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _currentSubtitle = 'Bạn: $text';
            _statusText = 'Mina AI đang suy nghĩ...';
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
    _audioVisualizerTimer?.cancel();
    _animationController.dispose();
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

    try {
      final success = await _xiaozhiService.connectVoiceCall();
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
            _startSpeaking();
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

  void _startSpeaking() {
    if (!_isSpeaking) {
      setState(() {
        _isSpeaking = true;
        _statusText = 'Đang lắng nghe...';
      });

      _xiaozhiService
          .startListeningCall()
          .then((_) {
            if (mounted) {
              print('VoiceCall: Đã bắt đầu thu âm');
            }
          })
          .catchError((e) {
            print('VoiceCall: Bắt đầu thu âm thất bại: $e');
            if (mounted) {
              setState(() {
                _isSpeaking = false;
              });
            }
          });
    }
  }

  void _sendAbortMessage() {
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
        _startSpeaking();
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
      appBar: AppBar(
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF0A192F),
            ],
          ),
        ),
        child: SafeArea(
          child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
        ),
      ),
    ),
  );
}

  Widget _buildLandscapeLayout() {
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
          _startSpeaking();
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
        : (_isSpeaking
            ? 'Đang lắng nghe liên tục...'
            : (_isConnected ? 'Sẵn sàng • Chạm để nói' : _statusText));

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
            _startSpeaking();
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
          size: 54,
          onPressed: () async {
            _isManualExit = true;
            await _xiaozhiService.sendAbortMessage();
            if (mounted) Navigator.pop(context);
          },
        ),
        const SizedBox(width: 28),
        if (!_isConnected)
          _buildActionButton(
            icon: Icons.refresh_rounded,
            color: Colors.white,
            backgroundColor: const Color(0xFF10B981),
            label: 'Kết nối lại',
            size: 58,
            onPressed: _connectToVoiceService,
          )
        else
          _buildActionButton(
            icon: _isSpeaking ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: Colors.white,
            backgroundColor: _isSpeaking ? const Color(0xFF10B981) : const Color(0xFF64748B),
            label: _isSpeaking ? 'Đang nghe' : 'Tạm dừng',
            size: 58,
            onPressed: () {
              if (_isSpeaking) {
                _xiaozhiService.stopListeningCall();
                setState(() {
                  _isSpeaking = false;
                  _statusText = 'Tạm dừng (Chạm để nghe)';
                });
              } else {
                _startSpeaking();
              }
            },
          ),
        const SizedBox(width: 28),
        _buildActionButton(
          icon: Icons.pan_tool_rounded,
          color: Colors.white,
          backgroundColor: const Color(0xFFF59E0B),
          label: 'Ngắt lời',
          size: 54,
          onPressed: _sendAbortMessage,
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
