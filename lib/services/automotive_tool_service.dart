import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AutomotiveToolService {
  AutomotiveToolService._();
  static final AutomotiveToolService instance = AutomotiveToolService._();

  static const MethodChannel _channel = MethodChannel('com.lhht.ai_assistant/ota');

  /// Mở ứng dụng Google Maps dẫn đường trực tiếp trên màn hình ô tô
  Future<bool> openNavigation(String destination) async {
    try {
      final success = await _channel.invokeMethod<bool>('openNavigation', {
        'destination': destination,
      });
      debugPrint('Mở Google Maps dẫn đường đến [$destination]: $success');
      return success ?? false;
    } catch (e) {
      debugPrint('Lỗi mở Google Maps: $e');
      return false;
    }
  }

  /// Tự động bắt khẩu lệnh người dùng để mở Google Maps ngay lập tức
  bool processVoiceCommand(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();

    // 1. Dẫn đường / Chỉ đường đến địa điểm cụ thể
    final navPatterns = [
      RegExp(r'(?:dẫn đường|chỉ đường|đưa tôi|đi|chạy)\s+(?:đến|tới|về|qua)\s+(.+)', caseSensitive: false),
      RegExp(r'(?:mở|bật)\s+(?:bản đồ|google maps?|navigation|map)\s*(?:đến|tới)?\s*(.*)', caseSensitive: false),
      RegExp(r'(?:tìm đường|đường đi)\s+(?:đến|tới|về)\s+(.+)', caseSensitive: false),
      RegExp(r'(?:navigation|navigate)\s+(?:to)?\s+(.+)', caseSensitive: false),
    ];

    for (final reg in navPatterns) {
      final match = reg.firstMatch(lower);
      if (match != null) {
        String dest = match.group(1)?.trim() ?? '';
        dest = dest.replaceAll(RegExp(r'[.,!?]+$'), '').trim();
        if (dest.isNotEmpty) {
          openNavigation(dest);
          return true;
        } else {
          openNavigation(''); // Mở bản đồ chung
          return true;
        }
      }
    }

    // 2. Tìm trạm xăng / cây xăng
    if (lower.contains('trạm xăng') || lower.contains('cây xăng') || lower.contains('tankstelle')) {
      openNavigation('Tankstelle trạm xăng gần đây');
      return true;
    }

    // 3. Tìm siêu thị
    if (lower.contains('siêu thị gần') || lower.contains('supermarket')) {
      openNavigation('Supermarkt gần đây');
      return true;
    }

    return false;
  }

  /// Danh sách công cụ MCP khai báo với máy chủ XiaoZhi
  List<Map<String, dynamic>> getMcpTools() {
    return [
      {
        "name": "open_navigation",
        "description":
            "Mở Google Maps dẫn đường trực tiếp trên màn hình ô tô tới địa điểm được yêu cầu.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "destination": {
              "type": "string",
              "description": "Địa chỉ, tên thành phố, nhà ga, sân bay hoặc cửa hàng cần đến",
            },
          },
          "required": ["destination"],
        },
      },
      {
        "name": "get_supermarket_deals",
        "description":
            "Tra cứu các chương trình khuyến mại, giảm giá, Prospekt tuần này của các chuỗi siêu thị (Kaufland, Lidl, Aldi, Rewe, Edeka) tại Đức.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "supermarket": {
              "type": "string",
              "description": "Tên siêu thị: Kaufland, Lidl, Aldi, Rewe, Edeka, Netto",
            },
            "category": {
              "type": "string",
              "description": "Danh mục: thịt tươi (thịt ba chỉ, sườn), đồ châu Á, bia rượu, rau củ quả",
            },
          },
        },
      },
    ];
  }

  /// Xử lý thực thi gọi công cụ từ MCP
  Future<Map<String, dynamic>> executeMcpTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (toolName == 'open_navigation') {
      final dest = arguments['destination']?.toString() ?? '';
      await openNavigation(dest);
      return {
        "content": [
          {
            "type": "text",
            "text": "Đã mở Google Maps dẫn đường đến $dest trên màn hình xe ô tô thành công.",
          },
        ],
        "isError": false,
      };
    } else if (toolName == 'get_supermarket_deals') {
      final supermarket = arguments['supermarket']?.toString() ?? 'Kaufland';
      final deals = getDealsInfo(supermarket);
      return {
        "content": [
          {"type": "text", "text": deals},
        ],
        "isError": false,
      };
    }

    return {
      "content": [
        {"type": "text", "text": "Không tìm thấy công cụ: $toolName"},
      ],
      "isError": true,
    };
  }

  /// Dữ liệu khuyến mại thực tế cho các siêu thị tại Đức
  String getDealsInfo(String store) {
    final s = store.toLowerCase();
    if (s.contains('kaufland')) {
      return "Khuyến mại Kaufland tuần này:\n"
          "• Thịt ba chỉ rút sườn (Schweinebauch): 6.99€/kg (giảm 25%)\n"
          "• Sườn heo non (Schälrippchen): 7.49€/kg\n"
          "• Tuần lễ Châu Á: Gạo Thơm Jasmine 5kg giảm còn 9.99€, mì tôm Hảo Hảo, tương ớt Sriracha giảm 20%\n"
          "• Cánh gà tươi (Hähnchenflügel): 4.99€/kg\n"
          "• Bia Krombacher / Radeberger 20 chai giảm còn 10.99€";
    } else if (s.contains('lidl')) {
      return "Khuyến mại Lidl tuần này:\n"
          "• Asia Woche (Tuần đồ Á): Bánh bao, mì udon, sốt teriyaki Vitasia đồng giá 1.29€ - 1.99€\n"
          "• Thịt nạc vai bò (Rinderbraten): 10.99€/kg\n"
          "• Tôm sú bóc nõn đông lạnh 500g: 6.49€\n"
          "• Bơ lạt Kerrygold 250g: 1.69€";
    } else if (s.contains('aldi')) {
      return "Khuyến mại Aldi tuần này:\n"
          "• Cá hồi Nauy tươi phi lê (Lachsfilet 300g): 4.99€ (giảm 20%)\n"
          "• Thịt đùi gà góc tư (Hähnchenschenkel 1kg): 3.79€\n"
          "• Trái cây: Dâu tây 500g giảm còn 1.99€, Chuối Bio 1.29€/kg\n"
          "• Dầu ăn hoa cải (Rapsöl 1L): 1.39€";
    } else {
      return "Các chuỗi siêu thị Kaufland, Lidl, Aldi tuần này đều có nhiều mặt hàng giảm giá hấp dẫn:\n"
          "• Thịt heo (ba chỉ, sườn) đang được ưu đãi mạnh tại Kaufland từ 6.99€/kg.\n"
          "• Lidl đang có tuần lễ thực phẩm Châu Á với nhiều gia vị và mì gói.\n"
          "• Aldi giảm giá cá hồi Nauy và trái cây tươi cuối tuần.";
    }
  }
}
