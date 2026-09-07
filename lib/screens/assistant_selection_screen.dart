import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/assistant_persona.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/models/message.dart';
import 'package:ai_assistant/models/xiaozhi_config.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/providers/config_provider.dart';
import 'package:ai_assistant/screens/chat_screen.dart';
import 'package:ai_assistant/screens/voice_call_screen.dart';
import 'package:ai_assistant/services/ota_service.dart';
import 'package:ai_assistant/services/xiaozhi_activation_service.dart';

class AssistantSelectionScreen extends StatefulWidget {
  final bool isModal;

  const AssistantSelectionScreen({super.key, this.isModal = false});

  @override
  State<AssistantSelectionScreen> createState() =>
      _AssistantSelectionScreenState();
}

class _AssistantSelectionScreenState extends State<AssistantSelectionScreen> {
  String _selectedCategory = 'Tất cả';

  @override
  void initState() {
    super.initState();
    // Tự động kiểm tra bản cập nhật sau khi vào app 3 giây (chạy ngầm)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        OtaService.instance.checkForUpdate(context, manual: false);
      }
    });
  }

  static const List<String> _categories = [
    'Tất cả',
    'Lái xe & GPS',
    'Công việc',
    'Học tập',
    'Mua sắm',
    'Đời sống',
    'Giải trí',
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final crossAxisCount = isWide ? 3 : 2;
    final childAspectRatio = isWide ? 2.3 : 1.45;

    final filteredPersonas =
        _selectedCategory == 'Tất cả'
            ? AssistantPersona.predefinedPersonas
            : AssistantPersona.predefinedPersonas
                .where((p) => p.category == _selectedCategory)
                .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: false,
        titleSpacing: widget.isModal ? 0 : 20,
        leading:
            widget.isModal
                ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87),
                  onPressed: () => Navigator.of(context).pop(),
                )
                : null,
        title: const Text(
          'Chọn trợ lý',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Color(0xFF1E293B),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_rounded, color: Color(0xFFD97706)),
            tooltip: 'Kích hoạt Tiếng Việt (xiaozhi.me)',
            onPressed: () {
              final configProvider = Provider.of<ConfigProvider>(context, listen: false);
              final mac = configProvider.xiaozhiConfigs.isNotEmpty
                  ? configProvider.xiaozhiConfigs.first.macAddress
                  : '';
              XiaozhiActivationService.instance.showActivationDialog(context, mac);
            },
          ),
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: Color(0xFF2563EB)),
            tooltip: 'Cập nhật OTA',
            onPressed: () {
              OtaService.instance.checkForUpdate(context, manual: true);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Hero Quick Connect Bar (Kiểu Lily AI: Bấm để kết nối & trò chuyện rảnh tay)
          _buildQuickConnectHero(context),

          // Banner nhắc kích hoạt Tiếng Việt
          _buildActivationBanner(context),

          // Category filter bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children:
                    _categories.map((category) {
                      final isSelected = _selectedCategory == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(
                            category,
                            style: TextStyle(
                              color:
                                  isSelected
                                      ? Colors.white
                                      : const Color(0xFF475569),
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFF2563EB),
                          backgroundColor: const Color(0xFFF1F5F9),
                          elevation: 0,
                          pressElevation: 0,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedCategory = category;
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),

          // Grid of personas
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: filteredPersonas.length,
              itemBuilder: (context, index) {
                final persona = filteredPersonas[index];
                return _buildPersonaCard(context, persona);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickConnectHero(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            final defaultPersona = AssistantPersona.predefinedPersonas.first;
            _onSelectPersona(context, defaultPersona, startVoiceCall: true);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                // Glowing mic icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic_none_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Bấm vào đây để kết nối',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Đàm thoại ô tô rảnh tay liên tục • Luôn lắng nghe',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bắt đầu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivationBanner(BuildContext context) {
    final configProvider = Provider.of<ConfigProvider>(context);
    final mac =
        configProvider.xiaozhiConfigs.isNotEmpty
            ? configProvider.xiaozhiConfigs.first.macAddress
            : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Material(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            XiaozhiActivationService.instance.showActivationDialog(context, mac);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.vpn_key_rounded, color: Color(0xFFD97706), size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Kích hoạt Tiếng Việt: Chạm để lấy Mã 6 số liên kết xiaozhi.me',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Lấy mã',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonaCard(BuildContext context, AssistantPersona persona) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1.5,
      shadowColor: Colors.black.withOpacity(0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _onSelectPersona(context, persona, startVoiceCall: true),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
          ),
          child: Stack(
            children: [
              // Hot badge or Crown
              if (persona.isHot)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF176),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '★ HOT',
                      style: TextStyle(
                        color: Color(0xFFB78103),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Circular icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: persona.iconBgColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          persona.icon,
                          color: persona.iconColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Name and badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              persona.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              persona.badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: persona.iconColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Subtitle
                  Text(
                    persona.subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Bottom action row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          persona.category,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      // Quick call button
                      InkWell(
                        onTap:
                            () => _onSelectPersona(
                              context,
                              persona,
                              startVoiceCall: true,
                            ),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: persona.iconBgColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.phone_in_talk_rounded,
                            color: persona.iconColor,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSelectPersona(
    BuildContext context,
    AssistantPersona persona, {
    required bool startVoiceCall,
  }) async {
    final conversationProvider = Provider.of<ConversationProvider>(
      context,
      listen: false,
    );
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);

    // Look for existing conversation with this persona
    Conversation? targetConv;
    for (final conv in conversationProvider.conversations) {
      if (conv.personaId == persona.id) {
        targetConv = conv;
        break;
      }
    }

    // If not found, create one
    if (targetConv == null) {
      final configId =
          configProvider.xiaozhiConfigs.isNotEmpty
              ? configProvider.xiaozhiConfigs.first.id
              : 'default_mina_ai';

      targetConv = await conversationProvider.createConversation(
        title: persona.name,
        type: ConversationType.xiaozhi,
        configId: configId,
        personaId: persona.id,
      );

      // Add persona greeting message
      await conversationProvider.addMessage(
        conversationId: targetConv.id,
        role: MessageRole.assistant,
        content: persona.greetingMessage,
      );
    }

    if (!context.mounted) return;

    if (startVoiceCall) {
      final effectiveConfig = configProvider.xiaozhiConfigs.firstWhere(
        (c) => c.id == targetConv!.configId,
        orElse:
            () =>
                configProvider.xiaozhiConfigs.isNotEmpty
                    ? configProvider.xiaozhiConfigs.first
                    : XiaozhiConfig(
                      id: 'default_mina_ai',
                      name: 'Mina AI',
                      websocketUrl: 'wss://api.tenclass.net/xiaozhi/v1/',
                      macAddress: '24:dc:c3:01:02:03',
                      token: 'test-token',
                    ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => VoiceCallScreen(
                conversation: targetConv!,
                xiaozhiConfig: effectiveConfig,
              ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(conversation: targetConv!),
        ),
      );
    }
  }
}
