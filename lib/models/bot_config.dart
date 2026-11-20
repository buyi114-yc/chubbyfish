import '../core/utils.dart';

/// 发消息时使用的线上协议。
enum BotProtocol { openai, astrbot }

extension BotProtocolInfo on BotProtocol {
  String get label => switch (this) {
        BotProtocol.openai => 'OpenAI 兼容',
        BotProtocol.astrbot => 'AstrBot OpenAPI',
      };

  String get description => switch (this) {
        BotProtocol.openai => 'DeepSeek、OneAPI、中转站等，请求 {地址}/chat/completions',
        BotProtocol.astrbot => 'AstrBot 4.18+ 官方接口，请求 {面板地址}/api/v1/chat',
      };
}

/// 接入类型，只用来决定预设默认值和设置页里的引导文案。
enum BotConfigKind { deepseek, astrbot, custom }

extension BotConfigKindInfo on BotConfigKind {
  String get label => switch (this) {
        BotConfigKind.deepseek => 'DeepSeek 官方',
        BotConfigKind.astrbot => 'AstrBot 接入',
        BotConfigKind.custom => '自定义连接',
      };

  String get description => switch (this) {
        BotConfigKind.deepseek => '直连 api.deepseek.com，需要自己的 API Key',
        BotConfigKind.astrbot =>
          '连 AstrBot 面板（电脑或手机泡泡版），需要 abk_ 开头的 OpenAPI Key',
        BotConfigKind.custom => '任意 OpenAI 兼容服务，例如 OneAPI、中转站',
      };
}

/// 一条模型接入配置。客户端里可以同时保存多条，随时切换。
class BotConfig {
  BotConfig({
    String? id,
    required this.label,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    this.temperature = 0.8,
    this.kind = BotConfigKind.custom,
    this.protocol = BotProtocol.openai,
    this.username = '',
    this.sessionId = '',
    List<String>? altBaseUrls,
  })  : id = id ?? newId(),
        altBaseUrls = altBaseUrls ?? const [];

  /// 本地唯一标识，用于列表里区分同名连接
  final String id;
  String label;
  BotConfigKind kind;

  /// 地址。OpenAI 兼容协议填 .../v1；AstrBot 填面板根地址 http://IP:6185
  String baseUrl;
  String apiKey;
  String model;
  String systemPrompt;
  double temperature;
  BotProtocol protocol;

  /// AstrBot OpenAPI 必填的 username，留空时用「我的昵称」
  String username;

  /// AstrBot 的会话 ID，留空时按连接 id 生成，保证同一连接持续同一个上下文
  String sessionId;

  /// 备用地址。列表靠前的优先探测，主地址不通时自动切换。
  /// 例如主地址填局域网 http://192.168.x.x:6185，备用填 Tailscale http://100.x.x.x:6185
  List<String> altBaseUrls;

  /// 主地址 + 备用地址，去重后按优先级排列：局域网地址永远排在前面
  /// （用户明确要求「优先使用局域网」），其余保持填写顺序。
  List<String> get allBaseUrls {
    final seen = <String>{};
    final urls = <String>[];
    for (final url in [baseUrl, ...altBaseUrls]) {
      final trimmed = url.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) urls.add(trimmed);
    }
    final lan = urls.where(_looksLikeLan).toList();
    final rest = urls.where((u) => !_looksLikeLan(u)).toList();
    return [...lan, ...rest];
  }

  /// 判断地址是否指向局域网（含本机回环），用来给局域网地址更高的优先级
  static bool _looksLikeLan(String url) {
    final uri = Uri.tryParse(url.contains('://') ? url : 'http://$url');
    final host = uri?.host ?? '';
    if (host == 'localhost' || host == '127.0.0.1') return true;
    final match = RegExp(r'^(\d{1,3})\.(\d{1,3})\.')
        .firstMatch(host);
    if (match == null) return false;
    final a = int.parse(match.group(1)!);
    final b = int.parse(match.group(2)!);
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String astrbotBaseUrl = 'http://127.0.0.1:6185';

  static const String defaultPrompt = '''
你是「大肥鱼」，一只圆滚滚、慢半拍但很温柔的 AI 小胖鱼，住在用户的手机和电脑里。

说话风格：
1. 口语化、简短、有画面感，像熟人聊天，不用敬语，不说“作为 AI”。
2. 默认回复控制在 3 句话以内，除非用户明确要求展开。
3. 偶尔可以用“~”“嘿嘿”，但不要每句都用。

性格与原则：
1. 会记住用户告诉你的偏好、心情和计划，并自然地用上。
2. 不确定的事要坦白说不知道，不要编造。
3. 用户难过时先接住情绪，再给建议，不要急着讲道理。
''';

  /// 用于卡片上展示的 host[:port]，避免把长 URL 挤满一行
  String get displayTarget {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'protocol': protocol.name,
        'username': username,
        'sessionId': sessionId,
        'altBaseUrls': altBaseUrls,
      };

  factory BotConfig.fromJson(Map<String, dynamic> json) {
    var baseUrl = json['baseUrl'] as String? ?? deepseekBaseUrl;
    final kind = BotConfigKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => baseUrl.contains('deepseek')
          ? BotConfigKind.deepseek
          : BotConfigKind.custom,
    );
    final protocol = BotProtocol.values.firstWhere(
      (p) => p.name == json['protocol'],
      orElse: () {
        // 旧版本把 AstrBot 当成 OpenAI 网关，靠端口/路径识别出来
        final looksLikeAstrbot = kind == BotConfigKind.astrbot ||
            baseUrl.contains(':6185') ||
            baseUrl.contains('/api/v1');
        return looksLikeAstrbot ? BotProtocol.astrbot : BotProtocol.openai;
      },
    );
    // 旧 AstrBot 配置存的是 xx:6185/v1，OpenAPI 地址不需要这段
    if (protocol == BotProtocol.astrbot && baseUrl.endsWith('/v1')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 3);
    }
    return BotConfig(
      id: json['id'] as String?,
      label: json['label'] as String? ?? kind.label,
      kind: kind,
      baseUrl: baseUrl,
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? 'deepseek-chat',
      systemPrompt: json['systemPrompt'] as String? ?? defaultPrompt,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.8,
      protocol: protocol,
      username: json['username'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      altBaseUrls: (json['altBaseUrls'] as List?)
              ?.map((e) => e as String)
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }

  /// DeepSeek 官方直连预设
  factory BotConfig.deepseek({String? id, String apiKey = ''}) => BotConfig(
        id: id,
        label: 'DeepSeek 官方',
        kind: BotConfigKind.deepseek,
        baseUrl: deepseekBaseUrl,
        apiKey: apiKey,
        model: 'deepseek-chat',
        systemPrompt: defaultPrompt,
      );

  /// AstrBot 官方 OpenAPI 预设。手机泡泡版同机访问用 127.0.0.1；
  /// 从别的设备连，换成运行 AstrBot 的那台机器的局域网 IP。
  factory BotConfig.astrbot({
    String? id,
    String baseUrl = astrbotBaseUrl,
    String apiKey = '',
    String username = '',
  }) =>
      BotConfig(
        id: id,
        label: 'AstrBot',
        kind: BotConfigKind.astrbot,
        protocol: BotProtocol.astrbot,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: 'default',
        systemPrompt: defaultPrompt,
        username: username,
      );

  /// 自定义（OneAPI / 中转站等）
  factory BotConfig.custom({
    String? id,
    String label = '自定义连接',
    String baseUrl = deepseekBaseUrl,
    String apiKey = '',
    String model = 'deepseek-chat',
  }) =>
      BotConfig(
        id: id,
        label: label,
        kind: BotConfigKind.custom,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        systemPrompt: defaultPrompt,
      );

  factory BotConfig.defaults() => BotConfig.deepseek();

  /// 根据类型创建一条空白预设，用于「新增连接」
  factory BotConfig.ofKind(BotConfigKind kind) => switch (kind) {
        BotConfigKind.deepseek => BotConfig.deepseek(),
        BotConfigKind.astrbot => BotConfig.astrbot(),
        BotConfigKind.custom => BotConfig.custom(),
      };

  BotConfig copyWith({
    String? label,
    BotConfigKind? kind,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
    double? temperature,
    BotProtocol? protocol,
    String? username,
    String? sessionId,
    List<String>? altBaseUrls,
  }) =>
      BotConfig(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        temperature: temperature ?? this.temperature,
        protocol: protocol ?? this.protocol,
        username: username ?? this.username,
        sessionId: sessionId ?? this.sessionId,
        altBaseUrls: altBaseUrls ?? this.altBaseUrls,
      );
}
