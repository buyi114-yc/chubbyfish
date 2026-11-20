import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_storage.dart';
import '../core/astrbot_client.dart';
import '../core/llm_client.dart';
import '../core/media_store.dart';
import '../core/notification_service.dart';
import '../core/utils.dart';
import '../models/bot_config.dart';
import '../models/chat_message.dart';
import '../models/chat_theme.dart';
import '../models/moment.dart';
import '../models/profile.dart';

enum Presence { online, away, dnd, offline }

extension PresenceInfo on Presence {
  String get label => switch (this) {
        Presence.online => '在线',
        Presence.away => '离开',
        Presence.dnd => '勿扰',
        Presence.offline => '离线',
      };

  Color get color => switch (this) {
        Presence.online => const Color(0xFF3CCB7F),
        Presence.away => const Color(0xFFF0B429),
        Presence.dnd => const Color(0xFFEA5455),
        Presence.offline => const Color(0xFF8A94A6),
      };
}

/// 全局状态：资料、主题、消息、动态、在线状态、模型接入配置。
/// 所有上层 UI 只依赖此对象，替换存储/网络实现时不需要改页面。
class AppState extends ChangeNotifier {
  AppState({
    required this.storage,
    required this.mediaStore,
    required this.notifications,
    LlmClient? client,
    AstrBotClient? astrbotClient,
  })  : _client = client ?? LlmClient(),
        _astrbot = astrbotClient ?? AstrBotClient(mediaStore: mediaStore);

  final AppStorage storage;
  final MediaStore mediaStore;
  final NotificationService notifications;
  final LlmClient _client;
  final AstrBotClient _astrbot;

  UserProfile user = UserProfile(name: '我');
  BotProfile bot = BotProfile(name: '大肥鱼');

  /// 可保存多条接入，随时切换；至少保留一条
  List<BotConfig> connections = [BotConfig.defaults()];
  int activeIndex = 0;

  /// 当前生效的连接
  BotConfig get config {
    final index = activeIndex < 0
        ? 0
        : (activeIndex >= connections.length
            ? connections.length - 1
            : activeIndex);
    return connections[index];
  }

  ChatTheme theme = ChatTheme.presets.first;
  Presence presence = Presence.online;
  List<ChatMessage> messages = [];
  List<Moment> moments = [];

  /// 还没看过的大肥鱼动态 id，用来做动态图标的角标数量
  final Set<String> _unreadMomentIds = {};
  int get unreadMoments => _unreadMomentIds.length;

  /// 签名变更历史（最新在前），每条为 {signature, timestamp}。
  List<Map<String, dynamic>> signatureHistory = [];
  List<String> stickers = [];
  bool onboarded = false;
  int _replyCount = 0;
  bool get isReplying => _replyCount > 0;
  bool isForeground = true;
  String? lastError;

  // ---------------- 自主行为 ----------------
  /// 动态、主动消息、签名都由 AstrBot 插件在后台独立生成，
  /// 客户端只定时拉取结果，不再通过标签协议向模型索要内容。
  Timer? _autonomyTimer;
  // 轮询间隔拉长到 3 分钟：主动消息本来就稀疏，省电优先
  static const _autonomyInterval = Duration(minutes: 3);
  bool isAutonomousRunning = false;

  /// 多地址（局域网 / Tailscale）自动选路的结果缓存
  String? _pickedBaseUrl;
  String? _pickedFor;
  DateTime? _pickedAt;
  static const _pickTtl = Duration(seconds: 60);

  List<ChatTheme> get presets => ChatTheme.presets;

  static const _kUser = 'user_profile';
  static const _kBot = 'bot_profile';
  static const _kConfig = 'bot_config';
  static const _kConnections = 'bot_connections';
  static const _kActive = 'bot_active_index';
  static const _kTheme = 'chat_theme';
  static const _kMessages = 'chat_messages';
  static const _kMoments = 'moments';
  static const _kUnreadMoments = 'unread_moments';
  static const _kSigHistory = 'signature_history';
  static const _kPresence = 'presence';
  static const _kOnboarded = 'onboarded';

  String? get userSignature => user.signature;

  Future<void> load() async {
    try {
      final rawUser = storage.getString(_kUser);
      if (rawUser != null) {
        user = UserProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawUser) as Map));
      }
      final rawBot = storage.getString(_kBot);
      if (rawBot != null) {
        bot = BotProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawBot) as Map));
      }
      final rawConnections = storage.getString(_kConnections);
      if (rawConnections != null) {
        final list = (jsonDecode(rawConnections) as List)
            .whereType<Map>()
            .map((e) => BotConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty) connections = list;
      } else {
        // 兼容旧版本的单条配置
        final rawConfig = storage.getString(_kConfig);
        if (rawConfig != null) {
          connections = [
            BotConfig.fromJson(
                Map<String, dynamic>.from(jsonDecode(rawConfig) as Map)),
          ];
        }
      }
      final rawActive = storage.getString(_kActive);
      final storedIndex = int.tryParse(rawActive ?? '');
      if (storedIndex != null && storedIndex >= 0) {
        activeIndex = storedIndex >= connections.length ? 0 : storedIndex;
      }
      final rawTheme = storage.getString(_kTheme);
      if (rawTheme != null) {
        theme = ChatTheme.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawTheme) as Map));
      }
      final rawPresence = storage.getString(_kPresence);
      if (rawPresence != null) {
        presence = Presence.values.firstWhere(
          (p) => p.name == rawPresence,
          orElse: () => Presence.online,
        );
      }
      final rawMessages = storage.getString(_kMessages);
      if (rawMessages != null) {
        messages = (jsonDecode(rawMessages) as List)
            .whereType<Map>()
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => !(m.role == MessageRole.bot &&
                m.status == MessageStatus.sending &&
                m.text.isEmpty))
            .toList();
        for (final m in messages) {
          if (m.status == MessageStatus.sending) m.status = MessageStatus.sent;
        }
      }
      final rawMoments = storage.getString(_kMoments);
      if (rawMoments != null) {
        moments = (jsonDecode(rawMoments) as List)
            .whereType<Map>()
            .map((e) => Moment.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      final rawSig = storage.getString(_kSigHistory);
      if (rawSig != null) {
        signatureHistory = (jsonDecode(rawSig) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      final rawUnread = storage.getString(_kUnreadMoments);
      if (rawUnread != null) {
        _unreadMomentIds
          ..clear()
          ..addAll((jsonDecode(rawUnread) as List).map((e) => e.toString()));
      }
      onboarded = storage.getBool(_kOnboarded) ?? false;
    } catch (_) {
      // 本地数据损坏时保持默认值，不阻塞启动
    }
    stickers = await mediaStore.listFiles('stickers');
    notifyListeners();
    startAutonomousTimer();
    // 启动后从插件同步签名、动态与主动消息（延迟几秒，避免阻塞首屏）
    Future.delayed(const Duration(seconds: 6), syncAutonomy);
  }

  @override
  void dispose() {
    stopAutonomousTimer();
    super.dispose();
  }

  // ---------------- 资料 / 设置 ----------------

  Future<void> saveUser(UserProfile profile) async {
    user = profile;
    await storage.setString(_kUser, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  Future<void> saveBot(BotProfile profile) async {
    // 签名变更时记录历史
    if (profile.signature != bot.signature && profile.signature.isNotEmpty) {
      signatureHistory.insert(0, {
        'signature': profile.signature,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      // 只保留最近 30 条
      if (signatureHistory.length > 30) {
        signatureHistory.removeRange(30, signatureHistory.length);
      }
      await storage.setString(
        _kSigHistory,
        jsonEncode(signatureHistory),
      );
    }
    bot = profile;
    await storage.setString(_kBot, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  Future<void> saveConfig(BotConfig value) async {
    connections[_safeActiveIndex] = value;
    await _persistConnections();
    notifyListeners();
  }

  /// 新增一条连接并设为当前连接
  Future<void> addConnection(BotConfig value) async {
    connections.add(value);
    activeIndex = connections.length - 1;
    await _persistConnections();
    notifyListeners();
  }

  /// 修改指定连接（不改动当前选中）
  Future<void> updateConnection(int index, BotConfig value) async {
    if (index < 0 || index >= connections.length) return;
    connections[index] = value;
    await _persistConnections();
    notifyListeners();
  }

  Future<void> removeConnection(int index) async {
    if (connections.length <= 1) return;
    connections.removeAt(index);
    if (activeIndex > index) {
      activeIndex--;
    } else if (activeIndex >= connections.length) {
      activeIndex = connections.length - 1;
    }
    await _persistConnections();
    notifyListeners();
  }

  Future<void> setActiveConnection(int index) async {
    if (index < 0 || index >= connections.length) return;
    if (activeIndex == index) return;
    activeIndex = index;
    await _persistConnections();
    notifyListeners();
  }

  int get _safeActiveIndex {
    if (activeIndex < 0) return 0;
    if (activeIndex >= connections.length) return connections.length - 1;
    return activeIndex;
  }

  Future<void> _persistConnections() async {
    activeIndex = _safeActiveIndex;
    await storage.setString(
      _kConnections,
      jsonEncode(connections.map((e) => e.toJson()).toList()),
    );
    await storage.setString(_kActive, activeIndex.toString());
  }

  Future<void> saveTheme(ChatTheme value) async {
    theme = value;
    await storage.setString(_kTheme, jsonEncode(value.toJson()));
    notifyListeners();
  }

  Future<void> applyPreset(ChatTheme preset) => saveTheme(preset);

  Future<void> setPresence(Presence value) async {
    presence = value;
    await storage.setString(_kPresence, value.name);
    notifyListeners();
  }

  Future<void> setOnboarded() async {
    onboarded = true;
    await storage.setBool(_kOnboarded, true);
    notifyListeners();
  }

  void setForeground(bool value) {
    final wasForeground = isForeground;
    isForeground = value;
    if (value) {
      if (!wasForeground) {
        // 回前台：清掉通知栏残留，立刻补一次同步，并恢复定时轮询
        unawaited(notifications.cancelAll());
        startAutonomousTimer();
      }
    } else {
      // 退到后台也保持轮询：主动消息一到就能马上弹通知，
      // 不必等容易被系统延迟的 15 分钟后台任务（App 被杀时仍由它兜底）
      if (_autonomyTimer == null) startAutonomousTimer();
    }
  }

  // ---------------- 发送消息 ----------------

  Future<void> sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    await _pushMessage(ChatMessage(
      id: newId(),
      role: MessageRole.user,
      kind: MessageKind.text,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> sendImageFromFile(String sourcePath) async {
    final saved = await mediaStore.importFile(sourcePath, 'images');
    await sendImage(saved);
  }

  /// 发送一张已经存放在应用目录里的图片
  Future<void> sendImage(String storedPath) async {
    await _pushMessage(ChatMessage(
      id: newId(),
      role: MessageRole.user,
      kind: MessageKind.image,
      mediaPath: storedPath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    unawaited(_reportImageToBot('user', 'image'));
  }

  /// 图文一起发送：同一条消息里同时带文字和图片。
  ///
  /// 只有文字或只有图片时直接走原来的单类型发送。
  Future<void> sendRichMessage(String raw, String? storedImagePath) async {
    final text = raw.trim();
    final imagePath = storedImagePath;
    if (imagePath == null || imagePath.isEmpty) {
      await sendText(text);
      return;
    }
    if (text.isEmpty) {
      await sendImage(imagePath);
      return;
    }
    await _pushMessage(ChatMessage(
      id: newId(),
      role: MessageRole.user,
      kind: MessageKind.image,
      text: text,
      mediaPath: imagePath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    unawaited(_reportImageToBot('user', 'image'));
  }

  Future<void> sendSticker(String stickerPath) async {
    await _pushMessage(ChatMessage(
      id: newId(),
      role: MessageRole.user,
      kind: MessageKind.sticker,
      mediaPath: stickerPath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    unawaited(_reportImageToBot('user', 'sticker'));
  }

  /// 把图片消息按发送者记到插件里，让她分得清「自己发的图」和「用户发的图」。
  Future<void> _reportImageToBot(String role, String kind) async {
    if (config.protocol != BotProtocol.astrbot) return;
    try {
      final baseUrl = await _resolveBaseUrl();
      await _astrbot.pushChatLog(
        baseUrl,
        config.apiKey,
        role: role,
        kind: kind,
      );
    } catch (_) {
      // 上报失败不影响聊天
    }
  }

  /// 发送一段语音：先让 AstrBot 把语音转成文字，再把文字发给大肥鱼。
  ///
  /// 模型本身听不到音频，所以「收到语音」实际靠的就是这份转写；
  /// 转写结果同时存进消息里，点开语音气泡就能像微信一样看文字。
  Future<void> sendVoice(String sourcePath, int durationMs) async {
    final saved = await mediaStore.importFile(sourcePath, 'voices');
    var transcript = '';
    if (config.protocol == BotProtocol.astrbot) {
      try {
        final baseUrl = await _resolveBaseUrl();
        transcript = await _astrbot.transcribeVoice(
              baseUrl,
              config.apiKey,
              saved,
            ) ??
            '';
      } catch (_) {
        // 识别失败也照常发送，至少语音气泡还在
      }
    }
    await _pushMessage(ChatMessage(
      id: newId(),
      role: MessageRole.user,
      kind: MessageKind.voice,
      text: transcript,
      mediaPath: saved,
      durationMs: durationMs,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> importSticker(String sourcePath) async {
    await mediaStore.importFile(sourcePath, 'stickers');
    stickers = await mediaStore.listFiles('stickers');
    notifyListeners();
  }

  Future<void> _pushMessage(ChatMessage message) async {
    messages.add(message);
    notifyListeners();
    await _persistMessages();
    await _requestReply();
  }

  Future<void> _requestReply() async {
    final history =
        messages.where((m) => m.kind != MessageKind.system).toList();
    var botMessage = ChatMessage(
      id: newId(),
      role: MessageRole.bot,
      kind: MessageKind.text,
      text: '',
      status: MessageStatus.sending,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    messages.add(botMessage);
    _replyCount++;
    lastError = null;
    notifyListeners();

    if (config.protocol == BotProtocol.astrbot &&
        config.apiKey.trim().isEmpty) {
      botMessage.status = MessageStatus.failed;
      botMessage.text = '还没有配置 AstrBot 的 OpenAPI Key（abk_ 开头）。'
          '在 AstrBot WebUI 的「设置 → OpenAPI」创建后，填到「设置 → 接入」里～';
      _replyCount--;
      notifyListeners();
      await _persistMessages();
      return;
    }

    if (config.protocol == BotProtocol.openai && config.apiKey.trim().isEmpty) {
      botMessage.status = MessageStatus.failed;
      botMessage.text = '还没有配置 API Key。进入「设置 → 接入」填写后就能聊天啦～';
      _replyCount--;
      notifyListeners();
      await _persistMessages();
      return;
    }

    final buffer = StringBuffer();
    var thinkStripper = _ThinkStripper();
    // 大肥鱼一轮回复里可能包含多条独立消息：遇到分隔标记就结束当前气泡，
    // 下一条文本会新开一个气泡，做到「一条消息一个气泡」。
    var bubbleClosed = false;

    void appendText(String text) {
      if (bubbleClosed) {
        bubbleClosed = false;
        buffer.clear();
        thinkStripper = _ThinkStripper();
        botMessage = ChatMessage(
          id: newId(),
          role: MessageRole.bot,
          kind: MessageKind.text,
          text: '',
          status: MessageStatus.sending,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        messages.add(botMessage);
      }
      buffer.write(text);
      botMessage.text = thinkStripper.strip(buffer.toString());
      notifyListeners();
    }

    void endBubble() {
      if (botMessage.text.trim().isEmpty) return;
      botMessage.status = MessageStatus.sent;
      bubbleClosed = true;
      buffer.clear();
      thinkStripper = _ThinkStripper();
    }

    try {
      if (config.protocol == BotProtocol.astrbot) {
        // 多地址（局域网 / Tailscale）自动选路
        final primary = await _resolveBaseUrl();
        final candidates = config.allBaseUrls;
        final ordered = [primary, ...candidates.where((u) => u != primary)];

        // AstrBot 只负责这一轮的用户消息（文本或图片），上下文由它自己的 session 保存
        Future<void> sendTo(String baseUrl) async {
          final parts = await _buildAstrBotParts(baseUrl);
          await for (final chunk in _astrbot.streamChat(
            baseUrl: baseUrl,
            apiKey: config.apiKey,
            username: _astrbotUsername,
            sessionId: _astrbotSessionId,
            message: '',
            parts: parts,
          )) {
            if (chunk is AstrBotText) {
              appendText(chunk.text);
            } else if (chunk is AstrBotSegmentBreak) {
              endBubble();
            } else if (chunk is AstrBotImage) {
              // 大肥鱼回了一张图，单独起一条图片消息
              final img = ChatMessage(
                id: newId(),
                role: MessageRole.bot,
                kind: MessageKind.image,
                mediaPath: chunk.localPath,
                status: MessageStatus.sent,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
              messages.add(img);
              notifyListeners();
              // 记一笔：这张图是大肥鱼自己发的
              unawaited(_reportImageToBot('bot', 'image'));
            }
          }
        }

        Object? lastError;
        for (final baseUrl in ordered) {
          try {
            try {
              await sendTo(baseUrl);
            } on LlmException catch (e) {
              // 旧上下文里的工具调用配对被破坏时，服务端会一直 400。
              // 这种情况清掉服务端上下文再重试一次，用户无感。
              if (!_isToolHistoryBroken(e.message) ||
                  botMessage.text.trim().isNotEmpty) {
                rethrow;
              }
              final ok = await _astrbot.resetConversation(
                baseUrl,
                config.apiKey,
                _astrbotUsername,
                _astrbotSessionId,
              );
              if (!ok) rethrow;
              await sendTo(baseUrl);
            }
            if (baseUrl != primary) {
              _rememberPicked('${config.id}|${candidates.join('|')}', baseUrl);
            }
            lastError = null;
            break;
          } catch (e) {
            lastError = e;
            // 只有在还没吐出任何内容时，才换成另一个地址重试；
            // 已经流式输出过内容就不能重发，避免重复。
            if (!_isNetworkError(e) || botMessage.text.trim().isNotEmpty) {
              rethrow;
            }
            _invalidatePickedBaseUrl();
          }
        }
        if (lastError != null) throw lastError;
      } else {
        final recent = history.length > 24
            ? history.sublist(history.length - 24)
            : history;
        final payload = <Map<String, dynamic>>[
          {'role': 'system', 'content': _buildSystemPrompt()},
          ...recent.map((m) => m.toLlmMessage()),
        ];
        await for (final chunk in _client.streamChat(
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          model: config.model,
          messages: payload,
          temperature: config.temperature,
        )) {
          appendText(chunk);
        }
      }
      if (!bubbleClosed) {
        if (buffer.isEmpty) botMessage.text = '（大肥鱼这次没有回应…）';
        botMessage.status = MessageStatus.sent;
      }
    } catch (e) {
      // 请求失败（可能是换了网络环境，原地址不通了）：下次重新探测地址
      if (config.protocol == BotProtocol.astrbot) _invalidatePickedBaseUrl();
      if (!bubbleClosed) {
        botMessage.status = MessageStatus.failed;
        botMessage.text =
            botMessage.text.isEmpty ? '连接失败了：$e' : botMessage.text;
      }
      lastError = '$e';
      notifyListeners();
    } finally {
      _replyCount--;
      notifyListeners();
      await _persistMessages();
      if (botMessage.status == MessageStatus.sent) {
        // 桌面端：每次回复都播放提示音；移动端：仅后台时弹系统通知
        await notifications.showReply(
          title: bot.name,
          body: shortText(botMessage.text, 80),
          isForeground: isForeground,
        );
      }
      // 刚聊完立刻补拉一次收件箱：大肥鱼可能在回复里用工具主动发了消息，
      // 不等 3 分钟的轮询，避免出现「说发了但软件里看不到」。
      unawaited(syncAutonomy());
    }
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time =
        '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
    final buffer = StringBuffer(config.systemPrompt.trim());
    buffer.write('\n\n【实时情境】\n');
    buffer.write('- 用户当前状态：${presence.label}\n');
    buffer.write('- 当前时间：$time\n');
    if (user.signature.trim().isNotEmpty) {
      buffer.write('- 用户签名：${user.signature.trim()}\n');
    }
    buffer.write('- 你们正在专属聊天客户端里对话，不在 QQ。');
    return buffer.toString();
  }

  // ---------------- AstrBot OpenAPI 辅助 ----------------

  String get _astrbotUsername => _usernameFor(config);

  String get _astrbotSessionId {
    final sid = config.sessionId.trim();
    if (sid.isNotEmpty) return sid;
    // 用户名参与 session id，避免换昵称/QQ号后命中旧会话触发归属校验失败
    final who = _astrbotUsername;
    return 'chubbyfish-${config.id}-$who';
  }

  String _usernameFor(BotConfig value) {
    final name = value.username.trim();
    if (name.isNotEmpty) return name;
    // 留空时使用用户昵称，避免绑定任何固定账号
    final nickname = user.name.trim();
    return nickname.isEmpty ? 'chubbyfish_user' : nickname;
  }

  /// 选出当前能用的地址：主地址优先（一般填局域网），不通再依次试备用地址
  /// （一般是 Tailscale）。结果缓存 [_pickTtl]，请求失败时调用
  /// [_invalidatePickedBaseUrl] 让下次重新探测。
  Future<String> _resolveBaseUrl() async {
    final candidates = config.allBaseUrls;
    if (candidates.isEmpty || candidates.length == 1) {
      return candidates.isEmpty ? config.baseUrl : candidates.first;
    }
    final signature = '${config.id}|${candidates.join('|')}';
    final picked = _pickedBaseUrl;
    final at = _pickedAt;
    if (picked != null &&
        _pickedFor == signature &&
        at != null &&
        DateTime.now().difference(at) < _pickTtl) {
      return picked;
    }
    // 并行探测而不是一个个试：在移动流量下局域网地址会卡满 4 秒超时，
    // 串行探测会让用户白等，也容易误判成「都不通」。
    final probes = await Future.wait(
      candidates.map((url) => _astrbot.ping(url, config.apiKey)),
    );
    for (var i = 0; i < candidates.length; i++) {
      if (probes[i]) {
        _rememberPicked(signature, candidates[i]);
        return candidates[i];
      }
    }
    // 全都不通：先用主地址，让真正发请求时把错误暴露出来
    _rememberPicked(signature, candidates.first);
    return candidates.first;
  }

  void _rememberPicked(String signature, String url) {
    _pickedFor = signature;
    _pickedBaseUrl = url;
    _pickedAt = DateTime.now();
  }

  void _invalidatePickedBaseUrl() {
    _pickedFor = null;
    _pickedBaseUrl = null;
    _pickedAt = null;
  }

  /// 服务端保存的上下文里工具调用配对被破坏（assistant 的 tool_calls 后面缺 tool 消息）
  static bool _isToolHistoryBroken(String message) {
    final text = message.toLowerCase();
    return text.contains('must be followed by tool messages') ||
        text.contains('insufficient tool messages');
  }

  /// 请求失败是不是网络层问题（超时、连不上）。
  /// 只有这类错误换地址重试才有意义；模型报错、Key 无效换地址也没用。
  static bool _isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('clientexception') ||
        text.contains('连接超时') ||
        text.contains('网络不可达');
  }

  /// 把最近一条用户消息整理成 AstrBot 的消息分段。
  ///
  /// 图片/表情包会先上传到 AstrBot 再作为 image 分段发送，这样模型能真正
  /// 看到图；上传失败时退回文字描述，至少不会让对话断掉。
  Future<List<Map<String, dynamic>>> _buildAstrBotParts(String baseUrl) async {
    ChatMessage? last;
    for (final m in messages.reversed) {
      if (m.kind == MessageKind.system || m.role != MessageRole.user) continue;
      last = m;
      break;
    }
    if (last == null)
      return [
        {'type': 'plain', 'text': '你好'}
      ];

    if (last.kind == MessageKind.image || last.kind == MessageKind.sticker) {
      final path = last.mediaPath;
      final caption = last.text.trim();
      if (path != null && path.isNotEmpty) {
        final id = await _astrbot.uploadImage(
          baseUrl,
          config.apiKey,
          path,
        );
        if (id != null) {
          return [
            {'type': 'image', 'attachment_id': id},
            if (caption.isNotEmpty) {'type': 'plain', 'text': caption},
          ];
        }
      }
      final fallback =
          last.kind == MessageKind.image ? '（我发了一张图片）' : '（我发了一个表情包）';
      return [
        {
          'type': 'plain',
          'text': caption.isEmpty ? fallback : '$fallback\n$caption',
        },
      ];
    }

    if (last.kind == MessageKind.voice) {
      final text = last.text.trim();
      return [
        {
          'type': 'plain',
          'text': text.isEmpty ? '（我刚发了一段语音，但这次没听清，你回我一下）' : text,
        },
      ];
    }

    final text = last.text.trim();
    return [
      {'type': 'plain', 'text': text.isEmpty ? '你好' : text},
    ];
  }

  Future<void> _persistMessages() async {
    final keep = messages.length > 300
        ? messages.sublist(messages.length - 300)
        : messages;
    await storage.setString(
      _kMessages,
      jsonEncode(keep.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    messages = [];
    await storage.setString(_kMessages, '[]');
    notifyListeners();
  }

  // ---------------- 动态 / 签名 ----------------

  Future<void> postMoment(String text, String? imageSourcePath,
      {bool isBot = false}) async {
    String? imagePath;
    if (imageSourcePath != null && imageSourcePath.isNotEmpty) {
      imagePath = await mediaStore.importFile(imageSourcePath, 'moments');
    }
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    moments.insert(
      0,
      Moment(
        id: newId(),
        text: text.trim(),
        imagePath: imagePath,
        createdAt: createdAt,
        isBot: isBot,
      ),
    );
    await storage.setString(
        _kMoments, jsonEncode(moments.map((e) => e.toJson()).toList()));
    notifyListeners();
    if (!isBot) {
      // 让大肥鱼知道这条动态；服务端会按「动态」而不是对话来记
      unawaited(_pushMomentToBot(text.trim(), createdAt,
          hasImage: imagePath != null));
    }
  }

  Future<void> _pushMomentToBot(
    String text,
    int createdAt, {
    required bool hasImage,
  }) async {
    if (text.isEmpty && !hasImage) return;
    if (config.protocol != BotProtocol.astrbot) return;
    try {
      final baseUrl = await _resolveBaseUrl();
      await _astrbot.pushMoment(
        baseUrl,
        config.apiKey,
        text.isEmpty ? '（发了一张图片）' : text,
        createdAt: createdAt,
        hasImage: hasImage,
      );
    } catch (_) {
      // 同步失败不影响本地动态
    }
  }

  Future<void> toggleMomentLike(String id) async {
    final index = moments.indexWhere((m) => m.id == id);
    if (index == -1) return;
    moments[index].liked = !moments[index].liked;
    await storage.setString(
        _kMoments, jsonEncode(moments.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  // ---------------- 自主行为：发动态 / 主动发消息 / 改签名 ----------------

  /// 定时从插件拉取大肥鱼自己产生的内容（动态 / 主动消息 / 签名）。
  void startAutonomousTimer() {
    _autonomyTimer?.cancel();
    _autonomyTimer = null;
    _autonomyTimer = Timer.periodic(_autonomyInterval, (_) {
      syncAutonomy();
    });
    // 启动/回前台时先拉一次
    Future.delayed(const Duration(seconds: 3), syncAutonomy);
  }

  void stopAutonomousTimer() {
    _autonomyTimer?.cancel();
    _autonomyTimer = null;
  }

  /// 拉取插件产出的签名、动态和主动消息，并合并到本地状态。
  Future<void> syncAutonomy() async {
    if (isAutonomousRunning) return;
    if (config.protocol != BotProtocol.astrbot) return;
    isAutonomousRunning = true;
    try {
      final baseUrl = await _resolveBaseUrl();
      final feed = await _astrbot.fetchFeed(baseUrl);
      if (feed != null) await _applyFeed(feed);

      final inbox = await _astrbot.fetchInbox(baseUrl);
      if (feed == null && inbox.isEmpty) {
        // 两条都拿不到，大概率是地址不通（比如离开家后 Tailscale 没开），
        // 清掉选路缓存，下次重新探测
        _invalidatePickedBaseUrl();
      }
      final ackedIds = <String>[];
      for (final item in inbox) {
        final remoteId = (item['id'] ?? '').toString();
        final text = (item['text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        final localId = 'auto-$remoteId';
        if (remoteId.isNotEmpty) ackedIds.add(remoteId);
        if (messages.any((m) => m.id == localId)) continue;
        final createdAt = ((item['createdAt'] as num?)?.toInt() ?? 0) * 1000;
        final msg = ChatMessage(
          id: localId,
          role: MessageRole.bot,
          kind: MessageKind.text,
          text: text,
          status: MessageStatus.sent,
          createdAt:
              createdAt > 0 ? createdAt : DateTime.now().millisecondsSinceEpoch,
        );
        messages.add(msg);
        notifyListeners();
        await notifications.showReply(
          title: bot.name,
          body: shortText(text, 80),
          // 主动消息不是聊天回复：不管 App 在前台还是后台都要提醒
          isForeground: false,
        );
      }
      if (ackedIds.isNotEmpty) {
        await _astrbot.ackInbox(baseUrl, ackedIds);
        await _persistMessages();
      }
    } catch (_) {
      // 拉取失败静默处理，不打扰用户
    } finally {
      isAutonomousRunning = false;
    }
  }

  /// 应用插件返回的签名与动态。
  Future<void> _applyFeed(Map<String, dynamic> feed) async {
    final signature = (feed['signature'] ?? '').toString().trim();
    if (signature.isNotEmpty && signature != bot.signature) {
      await saveBot(bot.copyWith(signature: signature));
    }

    final rawMoments = feed['moments'];
    if (rawMoments is! List) return;
    final added = <Moment>[];
    for (final raw in rawMoments.whereType<Map>()) {
      final remoteId = (raw['id'] ?? '').toString();
      final text = (raw['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final localId = 'bot-$remoteId';
      // 同一个插件动态只导入一次；文本重复的也跳过，避免反复堆叠
      final exists = moments.any((m) => m.id == localId) ||
          moments.any((m) => m.isBot && m.text.trim() == text) ||
          added.any((m) => m.text.trim() == text);
      if (exists) continue;
      added.add(Moment(
        id: localId,
        text: text,
        imagePath: null,
        createdAt: ((raw['createdAt'] as num?)?.toInt() ?? 0) * 1000,
        liked: false,
        isBot: true,
      ));
    }
    if (added.isEmpty) return;
    // 插件返回的是从旧到新，这里翻转让最新的排在最前面
    moments.insertAll(0, added.reversed.toList());
    if (moments.length > 100) {
      moments.removeRange(100, moments.length);
    }
    for (final m in added) {
      _unreadMomentIds.add(m.id);
    }
    await storage.setString(
        _kMoments, jsonEncode(moments.map((e) => e.toJson()).toList()));
    await storage.setString(
        _kUnreadMoments, jsonEncode(_unreadMomentIds.toList()));
    notifyListeners();
    // 动态提醒：标题里标明是动态通知，正文给最新那条
    unawaited(notifications.showMoment(
      title: '动态通知 · ${bot.name}',
      body: added.length == 1
          ? shortText(added.last.text, 60)
          : '${bot.name} 发了 ${added.length} 条新动态',
    ));
  }

  /// 打开动态面板时调用：清掉角标，同时把通知栏里的动态通知删掉。
  Future<void> markMomentsRead() async {
    unawaited(notifications.cancelMoment());
    if (_unreadMomentIds.isEmpty) return;
    _unreadMomentIds.clear();
    await storage.setString(_kUnreadMoments, '[]');
    notifyListeners();
  }

  // ---------------- 接入测试 ----------------

  Future<String> testConnection({BotConfig? target}) async {
    final c = target ?? config;
    if (c.protocol == BotProtocol.astrbot) {
      if (c.apiKey.trim().isEmpty) {
        throw LlmException(
          '还没有填写 AstrBot 的 OpenAPI Key（abk_ 开头）。'
          '在 AstrBot WebUI 的「设置 → OpenAPI」创建后再试。',
        );
      }
      // 测当前连接时也走多地址：移动流量下局域网地址必然超时，
      // 不能只试主地址就把「客户端异常」直接抛给用户。
      final candidates = target == null ? config.allBaseUrls : c.allBaseUrls;
      // 先用 4 秒的轻量探测排除不可达地址，避免在死地址上等满超时
      final probes = await Future.wait(
        candidates.map((url) => _astrbot.ping(url, c.apiKey)),
      );
      final reachable = <String>[
        for (var i = 0; i < candidates.length; i++)
          if (probes[i]) candidates[i],
      ];
      final ordered = reachable.isEmpty ? candidates : reachable;

      // 用独立的测试身份，不要借主人的 QQ 号。
      // 否则「只回复两个字：连通」会以主人的身份写进 AstrBot 的会话历史，
      // 陪伴插件照着这段历史学，就会把这句话当成主人平时的说话习惯。
      const testUser = 'chubbyfish-selftest';
      Object? lastError;
      for (final baseUrl in ordered) {
        final testSession =
            'selftest-${c.id}-${DateTime.now().millisecondsSinceEpoch}';
        try {
          final reply = await _astrbot.complete(
            baseUrl: baseUrl,
            apiKey: c.apiKey,
            username: testUser,
            sessionId: testSession,
            message: '只回复两个字：连通',
          );
          if (target == null) {
            _rememberPicked('${c.id}|${candidates.join('|')}', baseUrl);
          }
          // 测完顺手删掉这条临时会话，避免在 AstrBot 里留下成堆的测试记录
          unawaited(
            _astrbot.resetConversation(
                baseUrl, c.apiKey, testUser, testSession),
          );
          final body =
              reply.trim().isEmpty ? '已连通，但 AstrBot 没有返回文本' : reply.trim();
          return '$body（$baseUrl）';
        } catch (e) {
          lastError = e;
        }
      }

      // 把每个地址的探测结果一并给出，方便判断是没配备用地址，
      // 还是备用地址本身也不通。
      final probeText = [
        for (var i = 0; i < candidates.length; i++)
          '· ${candidates[i]} → ${probes[i] ? '服务可达' : '无响应（7 秒超时）'}',
      ].join('\n');
      final tried = candidates.join('、');
      throw LlmException(
        '${candidates.length > 1 ? '两个地址都连不上' : '连不上 $tried'}：\n'
        '$probeText\n\n'
        '${candidates.length > 1 ? '如果是移动数据，确认手机上的 Tailscale 已连接。' : '不在同一个 Wi-Fi 时局域网地址是通不了的：要么连回 Wi-Fi，要么给电脑和手机都开 Tailscale，再把 Tailscale 地址填进「备用地址」。'}\n'
        '最后一次错误：$lastError',
      );
    }
    final reply = await _client.complete(
      baseUrl: c.baseUrl,
      apiKey: c.apiKey,
      model: c.model,
      messages: [
        {
          'role': 'user',
          'content': '只回复两个字：连通',
        }
      ],
      temperature: 0,
    );
    return reply.trim().isEmpty ? '（已连通，但模型没有返回内容）' : reply.trim();
  }
}

/// 从 LLM 回复中剥离 <think>...</think> 思考过程，支持流式输出时的未闭合标签。
class _ThinkStripper {
  final _closedThink = RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
  final _openThink = RegExp(r'<think>[\s\S]*$', caseSensitive: false);

  String strip(String text) {
    // 先移除完整的 <think>...</think> 块
    var result = text.replaceAll(_closedThink, '');
    // 再移除尚未闭合的 <think> 开头部分（流式输出过程中）
    result = result.replaceAll(_openThink, '');
    return result.trimLeft();
  }
}
