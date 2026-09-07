import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ActivationResult {
  final bool isActivated;
  final String? code;
  final String? message;
  final String? challenge;
  final String macAddress;
  final String? websocketUrl;
  final String? token;
  final String? error;

  ActivationResult({
    required this.isActivated,
    this.code,
    this.message,
    this.challenge,
    required this.macAddress,
    this.websocketUrl,
    this.token,
    this.error,
  });
}

class XiaozhiActivationService {
  XiaozhiActivationService._();
  static final XiaozhiActivationService instance = XiaozhiActivationService._();

  static const String _otaUrl = 'https://api.tenclass.net/xiaozhi/ota/';
  static const String _prefClientIdKey = 'xiaozhi_ota_client_id';

  Future<String> _getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? clientId = prefs.getString(_prefClientIdKey);
    if (clientId == null || clientId.isEmpty) {
      clientId = const Uuid().v4();
      await prefs.setString(_prefClientIdKey, clientId);
    }
    return clientId;
  }

  /// Kiểm tra trạng thái kích hoạt và lấy mã 6 chữ số từ máy chủ XiaoZhi
  Future<ActivationResult> checkActivation(String macAddress) async {
    try {
      final clientId = await _getClientId();

      final response = await http
          .post(
            Uri.parse(_otaUrl),
            headers: {
              'Device-Id': macAddress,
              'Client-Id': clientId,
              'Activation-Version': '1',
              'User-Agent': 'XiaoZhi/1.0.0',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final activation = data['activation'];
        final websocket = data['websocket'];

        if (activation != null && activation is Map) {
          final code = activation['code']?.toString();
          final message = activation['message']?.toString();
          final challenge = activation['challenge']?.toString();
          return ActivationResult(
            isActivated: false,
            code: code,
            message: message,
            challenge: challenge,
            macAddress: macAddress,
            websocketUrl: websocket?['url'],
            token: websocket?['token'],
          );
        } else {
          // Không có activation -> Thiết bị đã được liên kết với tài khoản / agent
          return ActivationResult(
            isActivated: true,
            macAddress: macAddress,
            websocketUrl: websocket?['url'],
            token: websocket?['token'],
          );
        }
      } else {
        return ActivationResult(
          isActivated: false,
          macAddress: macAddress,
          error: 'Mã lỗi máy chủ: ${response.statusCode}',
        );
      }
    } catch (e) {
      return ActivationResult(
        isActivated: false,
        macAddress: macAddress,
        error: 'Lỗi kết nối: $e',
      );
    }
  }

  /// Hiển thị hộp thoại Kích hoạt Tiếng Việt với mã 6 số
  Future<void> showActivationDialog(
    BuildContext context,
    String macAddress, {
    VoidCallback? onActivationSuccess,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => _ActivationDialog(
            macAddress: macAddress,
            onActivationSuccess: onActivationSuccess,
          ),
    );
  }
}

class _ActivationDialog extends StatefulWidget {
  final String macAddress;
  final VoidCallback? onActivationSuccess;

  const _ActivationDialog({
    required this.macAddress,
    this.onActivationSuccess,
  });

  @override
  State<_ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends State<_ActivationDialog> {
  bool _isLoading = true;
  ActivationResult? _result;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    setState(() {
      _isLoading = true;
    });

    final res = await XiaozhiActivationService.instance.checkActivation(
      widget.macAddress,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _result = res;
      });

      if (res.isActivated && widget.onActivationSuccess != null) {
        widget.onActivationSuccess!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.vpn_key_rounded,
                    color: Color(0xFF2563EB),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kích hoạt Tiếng Việt (Mina AI)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Liên kết thiết bị ô tô với bảng điều khiển xiaozhi.me',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Content
            if (_isLoading) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 3),
                    SizedBox(height: 16),
                    Text(
                      'Đang kiểm tra trạng thái trên máy chủ XiaoZhi...',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ] else if (_result != null && _result!.isActivated) ...[
              // Đã kích hoạt thành công
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF10B981),
                      size: 48,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Đã liên kết Tiếng Việt thành công!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Thiết bị MAC: ${widget.macAddress}\nĐã kết nối với trợ lý Mina AI. Giờ đây trợ lý sẽ nghe và trả lời 100% bằng Tiếng Việt.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF047857), height: 1.4),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Chưa kích hoạt -> Hiển thị mã 6 số
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'MÃ KÍCH HOẠT CỦA XE (6 CHỮ SỐ):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Code display box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _result?.code ?? '------',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                              color: Color(0xFF38BDF8),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                            tooltip: 'Sao chép mã',
                            onPressed: () {
                              if (_result?.code != null) {
                                Clipboard.setData(ClipboardData(text: _result!.code!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã sao chép mã kích hoạt!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Địa chỉ MAC: ${widget.macAddress}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Hướng dẫn từng bước
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.phone_android_rounded, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Kích hoạt bằng điện thoại (chỉ làm 1 lần):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildStepItem('1', 'Mở trình duyệt điện thoại vào:', 'https://xiaozhi.me'),
                    _buildStepItem('2', 'Đăng nhập và nhấp vào Trợ lý:', 'Mina AI'),
                    _buildStepItem('3', 'Bấm "Thêm thiết bị" và nhập mã 6 số ở trên.', ''),
                    _buildStepItem('4', 'Bấm Xác nhận trên web, sau đó bấm nút "Kiểm tra lại" dưới đây.', ''),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Kiểm tra trạng thái'),
                  onPressed: _fetchStatus,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(String number, String text, String highlight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.3),
                children: [
                  TextSpan(text: text),
                  if (highlight.isNotEmpty)
                    TextSpan(
                      text: ' $highlight',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
