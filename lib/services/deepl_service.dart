import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ai_assistant/config/api_keys.dart';

/// DeepL Translation Service — Dịch thuật Việt ↔ Đức chuyên nghiệp
/// Free tier: 500,000 ký tự/tháng — https://www.deepl.com/pro-api
class DeepLService {
  DeepLService._();
  static final DeepLService instance = DeepLService._();

  String get _apiKey => ApiKeys.deepl;

  /// Tự động chọn endpoint Free/Pro dựa vào key
  String get _baseUrl => _apiKey.endsWith(':fx')
      ? 'https://api-free.deepl.com'
      : 'https://api.deepl.com';

  /// Kiểm tra API key đã được cấu hình chưa
  bool get isConfigured => _apiKey.isNotEmpty;

  /// Dịch một hoặc nhiều đoạn text
  ///
  /// [texts] — Danh sách các đoạn text cần dịch (tối đa 50 đoạn/request)
  /// [targetLang] — Ngôn ngữ đích: 'DE' (Đức) hoặc 'VI' (Việt)
  /// [sourceLang] — Ngôn ngữ nguồn (tùy chọn, auto-detect nếu null)
  /// [formality] — Mức độ trang trọng cho tiếng Đức:
  ///   'default', 'more' (Sie/trang trọng), 'less' (Du/thân mật),
  ///   'prefer_more', 'prefer_less'
  Future<List<TranslationResult>> translate({
    required List<String> texts,
    required String targetLang,
    String? sourceLang,
    String formality = 'default',
  }) async {
    if (!isConfigured) {
      throw DeepLException('DeepL API key chưa được cấu hình. '
          'Vui lòng thêm DEEPL_API_KEY vào GitHub Secrets.');
    }

    if (texts.isEmpty) return [];

    try {
      final body = <String, dynamic>{
        'text': texts,
        'target_lang': targetLang.toUpperCase(),
      };

      if (sourceLang != null && sourceLang.isNotEmpty) {
        body['source_lang'] = sourceLang.toUpperCase();
      }

      // Formality chỉ hỗ trợ cho một số ngôn ngữ (DE, FR, ES, IT, PT, NL, PL, JA, RU)
      if (formality != 'default' && _supportsFormalityLang(targetLang)) {
        body['formality'] = formality;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/v2/translate'),
        headers: {
          'Authorization': 'DeepL-Auth-Key $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final List translations = data['translations'] ?? [];
        return translations.map((t) => TranslationResult(
          text: t['text'] ?? '',
          detectedSourceLang: t['detected_source_language'] ?? '',
        )).toList();
      } else {
        _handleError(response.statusCode, response.body);
        return []; // Unreachable, _handleError always throws
      }
    } catch (e) {
      if (e is DeepLException) rethrow;
      throw DeepLException('Lỗi kết nối DeepL: $e');
    }
  }

  /// Dịch nhanh 1 câu — helper tiện lợi
  Future<String> translateSingle({
    required String text,
    required String targetLang,
    String? sourceLang,
    String formality = 'default',
  }) async {
    if (text.trim().isEmpty) return '';
    final results = await translate(
      texts: [text],
      targetLang: targetLang,
      sourceLang: sourceLang,
      formality: formality,
    );
    return results.isNotEmpty ? results.first.text : '';
  }

  /// Kiểm tra quota đã sử dụng (ký tự)
  Future<UsageInfo> getUsage() async {
    if (!isConfigured) {
      return UsageInfo(characterCount: 0, characterLimit: 500000);
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v2/usage'),
        headers: {
          'Authorization': 'DeepL-Auth-Key $_apiKey',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UsageInfo(
          characterCount: data['character_count'] ?? 0,
          characterLimit: data['character_limit'] ?? 500000,
        );
      }
    } catch (e) {
      debugPrint('DeepL getUsage error: $e');
    }

    return UsageInfo(characterCount: 0, characterLimit: 500000);
  }

  /// Lấy danh sách ngôn ngữ được hỗ trợ
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    if (!isConfigured) return _defaultLanguages();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v2/languages'),
        headers: {
          'Authorization': 'DeepL-Auth-Key $_apiKey',
        },
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((l) => SupportedLanguage(
          code: l['language'] ?? '',
          name: l['name'] ?? '',
          supportsFormality: l['supports_formality'] ?? false,
        )).toList();
      }
    } catch (e) {
      debugPrint('DeepL getSupportedLanguages error: $e');
    }

    return _defaultLanguages();
  }

  /// Kiểm tra ngôn ngữ có hỗ trợ formality không
  bool _supportsFormalityLang(String lang) {
    const supported = ['DE', 'FR', 'IT', 'ES', 'NL', 'PL', 'PT', 'PT-BR', 'PT-PT', 'JA', 'RU'];
    return supported.contains(lang.toUpperCase());
  }

  /// Xử lý lỗi HTTP response từ DeepL
  void _handleError(int statusCode, String body) {
    switch (statusCode) {
      case 400:
        throw DeepLException('Yêu cầu không hợp lệ. Vui lòng kiểm tra lại nội dung.');
      case 403:
        throw DeepLException('API key không hợp lệ. Vui lòng kiểm tra lại DEEPL_API_KEY.');
      case 413:
        throw DeepLException('Nội dung quá dài. Vui lòng chia nhỏ đoạn text.');
      case 429:
        throw DeepLException('Quá nhiều yêu cầu. Vui lòng thử lại sau vài giây.');
      case 456:
        throw DeepLException('Đã hết quota tháng này (500,000 ký tự). '
            'Quota sẽ được reset vào đầu chu kỳ tiếp theo.');
      case 500:
      case 503:
        throw DeepLException('Máy chủ DeepL đang bảo trì. Vui lòng thử lại sau.');
      default:
        throw DeepLException('Lỗi DeepL ($statusCode): $body');
    }
  }

  /// Danh sách ngôn ngữ mặc định khi không kết nối được API
  List<SupportedLanguage> _defaultLanguages() {
    return [
      SupportedLanguage(code: 'VI', name: 'Tiếng Việt', supportsFormality: false),
      SupportedLanguage(code: 'DE', name: 'Tiếng Đức', supportsFormality: true),
      SupportedLanguage(code: 'EN', name: 'Tiếng Anh', supportsFormality: false),
      SupportedLanguage(code: 'FR', name: 'Tiếng Pháp', supportsFormality: true),
      SupportedLanguage(code: 'ZH', name: 'Tiếng Trung', supportsFormality: false),
      SupportedLanguage(code: 'JA', name: 'Tiếng Nhật', supportsFormality: true),
      SupportedLanguage(code: 'KO', name: 'Tiếng Hàn', supportsFormality: false),
    ];
  }
}

/// Kết quả dịch thuật
class TranslationResult {
  final String text;
  final String detectedSourceLang;

  TranslationResult({required this.text, required this.detectedSourceLang});
}

/// Thông tin sử dụng quota
class UsageInfo {
  final int characterCount;
  final int characterLimit;

  UsageInfo({required this.characterCount, required this.characterLimit});

  int get characterRemaining => characterLimit - characterCount;
  double get usagePercent => characterLimit > 0 ? (characterCount / characterLimit) * 100 : 0;
  bool get isExhausted => characterCount >= characterLimit;

  String get formattedUsage =>
      '${_formatNumber(characterCount)} / ${_formatNumber(characterLimit)} ký tự';

  String get formattedRemaining =>
      '${_formatNumber(characterRemaining)} ký tự còn lại';

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }
}

/// Ngôn ngữ được hỗ trợ
class SupportedLanguage {
  final String code;
  final String name;
  final bool supportsFormality;

  SupportedLanguage({
    required this.code,
    required this.name,
    required this.supportsFormality,
  });
}

/// Exception riêng cho DeepL
class DeepLException implements Exception {
  final String message;
  DeepLException(this.message);

  @override
  String toString() => 'DeepLException: $message';
}
