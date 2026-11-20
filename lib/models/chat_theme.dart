import 'package:flutter/material.dart';

/// 一套完整的聊天外观配置：背景 / 气泡 / 文字 / 强调色。
/// 所有颜色以 int(ARGB) 存储，方便直接序列化到本地。
class ChatTheme {
  const ChatTheme({
    required this.id,
    required this.name,
    required this.bgColor,
    this.bgColor2,
    this.bgImage,
    required this.bubbleUserColor,
    required this.bubbleBotColor,
    required this.userTextColor,
    required this.botTextColor,
    this.bubbleUserImage,
    this.bubbleBotImage,
    this.bubbleRadius = 16,
    this.isDark = true,
    required this.accentColor,
    this.fontFamily,
  });

  final String id;
  final String name;
  final int bgColor;
  final int? bgColor2;
  final String? bgImage;
  final int bubbleUserColor;
  final int bubbleBotColor;
  final int userTextColor;
  final int botTextColor;
  final String? bubbleUserImage;
  final String? bubbleBotImage;
  final double bubbleRadius;
  final bool isDark;
  final int accentColor;
  final String? fontFamily;

  Color get background => Color(bgColor);
  Color? get backgroundSecondary =>
      bgColor2 == null ? null : Color(bgColor2!);
  Color get userBubble => Color(bubbleUserColor);
  Color get botBubble => Color(bubbleBotColor);
  Color get userText => Color(userTextColor);
  Color get botText => Color(botTextColor);
  Color get accent => Color(accentColor);

  /// 界面通用文字颜色（标题栏、设置页等）
  Color get chromeText =>
      isDark ? const Color(0xFFEEEEEE) : const Color(0xFF20242C);

  ChatTheme copyWith({
    String? id,
    String? name,
    int? bgColor,
    int? bgColor2,
    String? bgImage,
    int? bubbleUserColor,
    int? bubbleBotColor,
    int? userTextColor,
    int? botTextColor,
    String? bubbleUserImage,
    String? bubbleBotImage,
    double? bubbleRadius,
    bool? isDark,
    int? accentColor,
    String? fontFamily,
    bool removeBgImage = false,
    bool removeBubbleUserImage = false,
    bool removeBubbleBotImage = false,
  }) {
    return ChatTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      bgColor: bgColor ?? this.bgColor,
      bgColor2: bgColor2 ?? this.bgColor2,
      bgImage: removeBgImage ? null : (bgImage ?? this.bgImage),
      bubbleUserColor: bubbleUserColor ?? this.bubbleUserColor,
      bubbleBotColor: bubbleBotColor ?? this.bubbleBotColor,
      userTextColor: userTextColor ?? this.userTextColor,
      botTextColor: botTextColor ?? this.botTextColor,
      bubbleUserImage:
          removeBubbleUserImage ? null : (bubbleUserImage ?? this.bubbleUserImage),
      bubbleBotImage:
          removeBubbleBotImage ? null : (bubbleBotImage ?? this.bubbleBotImage),
      bubbleRadius: bubbleRadius ?? this.bubbleRadius,
      isDark: isDark ?? this.isDark,
      accentColor: accentColor ?? this.accentColor,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bgColor': bgColor,
        'bgColor2': bgColor2,
        'bgImage': bgImage,
        'bubbleUserColor': bubbleUserColor,
        'bubbleBotColor': bubbleBotColor,
        'userTextColor': userTextColor,
        'botTextColor': botTextColor,
        'bubbleUserImage': bubbleUserImage,
        'bubbleBotImage': bubbleBotImage,
        'bubbleRadius': bubbleRadius,
        'isDark': isDark,
        'accentColor': accentColor,
        'fontFamily': fontFamily,
      };

  factory ChatTheme.fromJson(Map<String, dynamic> json) => ChatTheme(
        id: json['id'] as String? ?? 'custom',
        name: json['name'] as String? ?? '自定义',
        bgColor: json['bgColor'] as int? ?? 0xFF0B1220,
        bgColor2: json['bgColor2'] as int?,
        bgImage: json['bgImage'] as String?,
        bubbleUserColor: json['bubbleUserColor'] as int? ?? 0xFF2F7CF6,
        bubbleBotColor: json['bubbleBotColor'] as int? ?? 0xFF1B2B3D,
        userTextColor: json['userTextColor'] as int? ?? 0xFFF2F7FF,
        botTextColor: json['botTextColor'] as int? ?? 0xFFD7E5F5,
        bubbleUserImage: json['bubbleUserImage'] as String?,
        bubbleBotImage: json['bubbleBotImage'] as String?,
        bubbleRadius: (json['bubbleRadius'] as num?)?.toDouble() ?? 16,
        isDark: json['isDark'] as bool? ?? true,
        accentColor: json['accentColor'] as int? ?? 0xFF4FA3FF,
        fontFamily: json['fontFamily'] as String?,
      );

  /// 可选字体列表（系统内置字体名）。
  static const List<String> fontFamilies = [
    '默认',
    'Microsoft YaHei',
    'SimSun',
    'KaiTi',
    'SimHei',
    'FangSong',
    'STKaiti',
    'Arial',
    'Georgia',
    'Courier New',
  ];

  /// 内置 5 套预设主题，第一套是默认的黑白配色
  static const List<ChatTheme> presets = [
    ChatTheme(
      id: 'mono',
      name: '黑白',
      bgColor: 0xFF0A0A0A,
      bgColor2: 0xFF191919,
      bubbleUserColor: 0xFFF2F2F2,
      bubbleBotColor: 0xFF232323,
      userTextColor: 0xFF111111,
      botTextColor: 0xFFE8E8E8,
      bubbleRadius: 14,
      isDark: true,
      accentColor: 0xFF8C8C8C,
    ),
    ChatTheme(
      id: 'ocean',
      name: '深海蓝',
      bgColor: 0xFF08131F,
      bgColor2: 0xFF123048,
      bubbleUserColor: 0xFF2F7CF6,
      bubbleBotColor: 0xFF1B2B3D,
      userTextColor: 0xFFF2F7FF,
      botTextColor: 0xFFD7E5F5,
      bubbleRadius: 16,
      isDark: true,
      accentColor: 0xFF4FA3FF,
    ),
    ChatTheme(
      id: 'cream',
      name: '奶油暖阳',
      bgColor: 0xFFFBF6EE,
      bgColor2: 0xFFFFEFD9,
      bubbleUserColor: 0xFFF6B26B,
      bubbleBotColor: 0xFFFFFFFF,
      userTextColor: 0xFF4A2F16,
      botTextColor: 0xFF3C3C3C,
      bubbleRadius: 18,
      isDark: false,
      accentColor: 0xFFE9974F,
    ),
    ChatTheme(
      id: 'sakura',
      name: '樱花粉',
      bgColor: 0xFFFFF2F5,
      bgColor2: 0xFFFFE1E9,
      bubbleUserColor: 0xFFFF8FA8,
      bubbleBotColor: 0xFFFFFFFF,
      userTextColor: 0xFFFFF7F9,
      botTextColor: 0xFF4A3540,
      bubbleRadius: 20,
      isDark: false,
      accentColor: 0xFFFF7A9C,
    ),
    ChatTheme(
      id: 'midnight',
      name: '暗夜紫',
      bgColor: 0xFF0B0B0E,
      bgColor2: 0xFF17141F,
      bubbleUserColor: 0xFF6D5BD0,
      bubbleBotColor: 0xFF23222A,
      userTextColor: 0xFFF2F0FF,
      botTextColor: 0xFFD8D6E6,
      bubbleRadius: 14,
      isDark: true,
      accentColor: 0xFF9B8CFF,
    ),
  ];
}
