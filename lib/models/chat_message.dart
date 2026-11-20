enum MessageRole { user, bot }

enum MessageKind { text, image, voice, sticker, system }

enum MessageStatus { sending, sent, failed }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.kind,
    this.text = '',
    this.mediaPath,
    this.durationMs,
    this.status = MessageStatus.sent,
    required this.createdAt,
  });

  final String id;
  final MessageRole role;
  final MessageKind kind;
  String text;
  final String? mediaPath;
  final int? durationMs;
  MessageStatus status;
  final int createdAt;

  bool get isUser => role == MessageRole.user;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'kind': kind.name,
        'text': text,
        'mediaPath': mediaPath,
        'durationMs': durationMs,
        'status': status.name,
        'createdAt': createdAt,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => MessageRole.bot,
        ),
        kind: MessageKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => MessageKind.text,
        ),
        text: json['text'] as String? ?? '',
        mediaPath: json['mediaPath'] as String?,
        durationMs: json['durationMs'] as int?,
        status: MessageStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => MessageStatus.sent,
        ),
        createdAt: json['createdAt'] as int? ?? 0,
      );

  /// 转成 OpenAI 兼容的 message 结构。
  /// 图片/语音/表情暂以文字描述提交，等接入多模态或 ASR 后再替换成真正的 content 数组。
  Map<String, dynamic> toLlmMessage() {
    final roleName = isUser ? 'user' : 'assistant';
    String content;
    switch (kind) {
      case MessageKind.text:
        content = text;
        break;
      case MessageKind.image:
        content = text.isEmpty ? '（用户发送了一张图片）' : '$text（并发送了一张图片）';
        break;
      case MessageKind.voice:
        content = text.isEmpty
            ? '（用户发送了一段语音）'
            : '（语音转写）$text';
        break;
      case MessageKind.sticker:
        content = text.isEmpty ? '（用户发送了一个表情包）' : text;
        break;
      case MessageKind.system:
        content = text;
        break;
    }
    return {'role': roleName, 'content': content};
  }
}
