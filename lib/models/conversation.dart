enum ConversationType { dify, xiaozhi, minimax }

class Conversation {
  final String id;
  final String title;
  final ConversationType type;
  final String
  configId; // For both Xiaozhi and Dify conversations, references the config
  final DateTime lastMessageTime;
  final String lastMessage;
  final int unreadCount;
  final bool isPinned;
  final String personaId;

  Conversation({
    required this.id,
    required this.title,
    required this.type,
    this.configId = '',
    this.personaId = '',
    required this.lastMessageTime,
    required this.lastMessage,
    this.unreadCount = 0,
    this.isPinned = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      title: json['title'],
      type: ConversationType.values.byName(json['type']),
      configId: json['configId'] ?? '',
      personaId: json['personaId'] ?? '',
      lastMessageTime: DateTime.parse(json['lastMessageTime']),
      lastMessage: json['lastMessage'],
      unreadCount: json['unreadCount'] ?? 0,
      isPinned: json['isPinned'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type.name,
      'configId': configId,
      'personaId': personaId,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
      'isPinned': isPinned,
    };
  }

  Conversation copyWith({
    String? title,
    ConversationType? type,
    String? configId,
    String? personaId,
    DateTime? lastMessageTime,
    String? lastMessage,
    int? unreadCount,
    bool? isPinned,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      configId: configId ?? this.configId,
      personaId: personaId ?? this.personaId,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
