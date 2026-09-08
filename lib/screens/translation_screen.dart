import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ai_assistant/services/deepl_service.dart';

/// Màn hình dịch thuật Việt ↔ Đức chuyên nghiệp sử dụng DeepL API
class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final DeepLService _deepl = DeepLService.instance;

  String _sourceLang = 'VI';
  String _targetLang = 'DE';
  String _translatedText = '';
  String _formality = 'default'; // 'default', 'more' (Sie), 'less' (Du)
  bool _isTranslating = false;
  String? _errorMessage;
  UsageInfo? _usage;

  // Debounce cho auto-translate
  Timer? _autoTranslateTimer;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _autoTranslateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await _deepl.getUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {}
  }

  /// Hoán đổi ngôn ngữ nguồn ↔ đích
  void _swapLanguages() {
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;

      // Nếu có kết quả dịch, đưa kết quả vào input để dịch ngược
      if (_translatedText.isNotEmpty) {
        _inputController.text = _translatedText;
        _translatedText = '';
      }
    });
    // Auto-translate sau khi hoán đổi
    if (_inputController.text.trim().isNotEmpty) {
      _translate();
    }
  }

  /// Dịch text
  Future<void> _translate() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _translatedText = '';
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
      _errorMessage = null;
    });

    try {
      final result = await _deepl.translateSingle(
        text: text,
        targetLang: _targetLang,
        sourceLang: _sourceLang,
        formality: _formality,
      );

      if (mounted) {
        setState(() {
          _translatedText = result;
          _isTranslating = false;
        });
        // Refresh quota
        _loadUsage();
      }
    } on DeepLException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Lỗi kết nối: $e';
          _isTranslating = false;
        });
      }
    }
  }

  /// Auto-translate khi người dùng dừng gõ 1.5s
  void _onInputChanged(String text) {
    _autoTranslateTimer?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _translatedText = '';
        _errorMessage = null;
      });
      return;
    }
    _autoTranslateTimer = Timer(const Duration(milliseconds: 1500), _translate);
  }

  /// Copy text vào clipboard
  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Đã sao chép!'),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Paste text từ clipboard
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _inputController.text = data.text!;
      _translate();
    }
  }

  /// Xóa toàn bộ nội dung
  void _clearAll() {
    _inputController.clear();
    setState(() {
      _translatedText = '';
      _errorMessage = null;
    });
  }

  String _langName(String code) {
    switch (code.toUpperCase()) {
      case 'VI': return 'Tiếng Việt';
      case 'DE': return 'Tiếng Đức';
      case 'EN': return 'Tiếng Anh';
      case 'FR': return 'Tiếng Pháp';
      case 'ZH': return 'Tiếng Trung';
      case 'JA': return 'Tiếng Nhật';
      case 'KO': return 'Tiếng Hàn';
      default: return code;
    }
  }

  String _langFlag(String code) {
    switch (code.toUpperCase()) {
      case 'VI': return '🇻🇳';
      case 'DE': return '🇩🇪';
      case 'EN': return '🇬🇧';
      case 'FR': return '🇫🇷';
      case 'ZH': return '🇨🇳';
      case 'JA': return '🇯🇵';
      case 'KO': return '🇰🇷';
      default: return '🌍';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mina Phiên Dịch',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          // Nút xóa
          if (_inputController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all_rounded, color: Color(0xFF64748B)),
              tooltip: 'Xóa tất cả',
              onPressed: _clearAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // === LANGUAGE SELECTOR BAR ===
                  _buildLanguageBar(),
                  const SizedBox(height: 14),

                  // === INPUT CARD ===
                  _buildInputCard(),
                  const SizedBox(height: 10),

                  // === TRANSLATE BUTTON ===
                  _buildTranslateButton(),
                  const SizedBox(height: 10),

                  // === OUTPUT CARD ===
                  _buildOutputCard(),
                  const SizedBox(height: 14),

                  // === FORMALITY SELECTOR (chỉ hiện khi target là DE) ===
                  if (_targetLang == 'DE') ...[
                    _buildFormalitySelector(),
                    const SizedBox(height: 14),
                  ],

                  // === QUOTA INFO ===
                  if (_usage != null) _buildQuotaInfo(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Source language
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showLanguagePicker(isSource: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_langFlag(_sourceLang), style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(
                      _langName(_sourceLang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 20),
                  ],
                ),
              ),
            ),
          ),

          // Swap button
          GestureDetector(
            onTap: _swapLanguages,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22),
            ),
          ),

          // Target language
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showLanguagePicker(isSource: false),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_langFlag(_targetLang), style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(
                      _langName(_targetLang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  '${_langFlag(_sourceLang)} ${_langName(_sourceLang)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                // Paste button
                InkWell(
                  onTap: _pasteFromClipboard,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.paste_rounded, size: 18, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
          // Text input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              maxLines: 5,
              minLines: 3,
              onChanged: _onInputChanged,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _translate(),
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFF1E293B),
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'Nhập văn bản cần dịch...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          // Character count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              '${_inputController.text.length} ký tự',
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslateButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isTranslating ? null : _translate,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          disabledBackgroundColor: const Color(0xFF93C5FD),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
          shadowColor: const Color(0xFF2563EB).withOpacity(0.3),
        ),
        child: _isTranslating
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Đang dịch...', style: TextStyle(fontSize: 16)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.translate_rounded, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Dịch ngay',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOutputCard() {
    final hasResult = _translatedText.isNotEmpty;
    final hasError = _errorMessage != null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        color: hasError ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hasError
            ? Border.all(color: const Color(0xFFFCA5A5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  '${_langFlag(_targetLang)} ${_langName(_targetLang)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                if (hasResult) ...[
                  // Copy button
                  InkWell(
                    onTap: () => _copyToClipboard(_translatedText),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: Color(0xFF64748B)),
                          SizedBox(width: 4),
                          Text(
                            'Sao chép',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: hasError
                ? Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  )
                : hasResult
                    ? SelectableText(
                        _translatedText,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFF1E293B),
                          height: 1.5,
                        ),
                      )
                    : Text(
                        'Bản dịch sẽ hiện ở đây...',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 16,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormalitySelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Phong cách (Formality)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFormalityChip('default', 'Tự động', Icons.auto_awesome),
              const SizedBox(width: 8),
              _buildFormalityChip('less', 'Du (thân mật)', Icons.emoji_emotions_outlined),
              const SizedBox(width: 8),
              _buildFormalityChip('more', 'Sie (trang trọng)', Icons.business_center_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormalityChip(String value, String label, IconData icon) {
    final isSelected = _formality == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _formality = value);
          // Re-translate nếu đã có kết quả
          if (_translatedText.isNotEmpty) _translate();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuotaInfo() {
    final usage = _usage!;
    final percent = usage.usagePercent.clamp(0.0, 100.0);
    final color = percent > 80
        ? const Color(0xFFEF4444)
        : percent > 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              const Text(
                'Quota DeepL Free',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              Text(
                usage.formattedUsage,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            usage.formattedRemaining,
            style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker({required bool isSource}) {
    final languages = [
      ('VI', 'Tiếng Việt', '🇻🇳'),
      ('DE', 'Tiếng Đức', '🇩🇪'),
      ('EN', 'Tiếng Anh', '🇬🇧'),
      ('FR', 'Tiếng Pháp', '🇫🇷'),
      ('ZH', 'Tiếng Trung', '🇨🇳'),
      ('JA', 'Tiếng Nhật', '🇯🇵'),
      ('KO', 'Tiếng Hàn', '🇰🇷'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSource ? 'Chọn ngôn ngữ nguồn' : 'Chọn ngôn ngữ đích',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            ...languages.map((lang) => ListTile(
              leading: Text(lang.$3, style: const TextStyle(fontSize: 24)),
              title: Text(lang.$2, style: const TextStyle(fontWeight: FontWeight.w500)),
              trailing: (isSource ? _sourceLang : _targetLang) == lang.$1
                  ? const Icon(Icons.check_circle, color: Color(0xFF2563EB))
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                setState(() {
                  if (isSource) {
                    _sourceLang = lang.$1;
                  } else {
                    _targetLang = lang.$1;
                  }
                });
                Navigator.pop(context);
                if (_inputController.text.trim().isNotEmpty) {
                  _translate();
                }
              },
            )),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
