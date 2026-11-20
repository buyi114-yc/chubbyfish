import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bot_config.dart';
import '../../models/chat_theme.dart';
import '../../models/profile.dart';
import '../../state/app_state.dart';
import '../../widgets/avatar_view.dart';
import '../settings/connection_guide.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _index = 0;

  late final TextEditingController _myName;
  late final TextEditingController _signature;
  late final TextEditingController _botName;
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;

  String? _myAvatar;
  String? _botAvatar;

  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  /// 点了某张接入方式卡片后，记下它对应的协议，避免靠端口猜错
  BotProtocol? _pickedProtocol;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _myName = TextEditingController(text: state.user.name == '我' ? '' : state.user.name);
    _signature = TextEditingController(text: state.user.signature);
    _botName = TextEditingController(text: state.bot.name);
    _baseUrl = TextEditingController(text: state.config.baseUrl);
    _apiKey = TextEditingController(text: state.config.apiKey);
    _model = TextEditingController(text: state.config.model);
    _myAvatar = state.user.avatarPath;
    _botAvatar = state.bot.avatarPath;
  }

  @override
  void dispose() {
    _myName.dispose();
    _signature.dispose();
    _botName.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar({required bool mine}) async {
    final path = await context.read<AppState>().mediaStore.pickImage(
          'avatars',
          maxWidth: 512,
        );
    if (!mounted || path == null) return;
    setState(() {
      if (mine) {
        _myAvatar = path;
      } else {
        _botAvatar = path;
      }
    });
  }

  /// 从输入的地址判断是不是 AstrBot 面板（6185 端口或 /api/v1 路径）。
  ///
  /// 手机上的泡泡版走 127.0.0.1，端口也可能被改过，所以本机地址一律
  /// 按 AstrBot 处理——小渔窝的受众里没人会在手机本机跑 OpenAI 服务。
  bool _looksLikeAstrbot(String baseUrl) {
    final url = baseUrl.toLowerCase();
    if (url.contains('/api/v1')) return true;
    // 本机跑 Ollama 之类会带 /v1，不能因为 127.0.0.1 就当成 AstrBot
    if (url.contains('/v1') || url.contains('/chat/completions')) return false;
    return url.contains(':6185') ||
        url.contains('127.0.0.1') ||
        url.contains('localhost');
  }

  /// 协议：地址能明确判断就按地址，否则按用户点的接入方式
  BotProtocol _protocolFor(String baseUrl) {
    if (_looksLikeAstrbot(baseUrl)) return BotProtocol.astrbot;
    return _pickedProtocol ?? BotProtocol.openai;
  }

  Future<void> _test() async {
    final state = context.read<AppState>();
    final baseUrl = _baseUrl.text.trim().isEmpty
        ? BotConfig.deepseekBaseUrl
        : _baseUrl.text.trim();
    final protocol = _protocolFor(baseUrl);
    final isAstrbot = protocol == BotProtocol.astrbot;
    await state.saveConfig(
      state.config.copyWith(
        baseUrl: baseUrl,
        apiKey: _apiKey.text.trim(),
        protocol: protocol,
        model: _model.text.trim().isEmpty
            ? (isAstrbot ? 'default' : 'deepseek-chat')
            : _model.text.trim(),
      ),
    );
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final reply = await state.testConnection();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = reply;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = '$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _finish() async {
    final state = context.read<AppState>();
    setState(() => _testing = true);
    await state.saveUser(UserProfile(
      name: _myName.text.trim().isEmpty ? '我' : _myName.text.trim(),
      avatarPath: _myAvatar,
      signature: _signature.text.trim(),
    ));
    await state.saveBot(BotProfile(
      name: _botName.text.trim().isEmpty ? '大肥鱼' : _botName.text.trim(),
      avatarPath: _botAvatar,
    ));
    final baseUrl = _baseUrl.text.trim().isEmpty
        ? BotConfig.deepseekBaseUrl
        : _baseUrl.text.trim();
    final protocol = _protocolFor(baseUrl);
    final isAstrbot = protocol == BotProtocol.astrbot;
    final isDeepseek = baseUrl.contains('deepseek');
    await state.saveConfig(state.config.copyWith(
      label: isAstrbot
          ? 'AstrBot'
          : (isDeepseek ? 'DeepSeek 官方' : '自定义连接'),
      kind: isAstrbot
          ? BotConfigKind.astrbot
          : (isDeepseek ? BotConfigKind.deepseek : BotConfigKind.custom),
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: _apiKey.text.trim(),
      model: _model.text.trim().isEmpty
          ? (isAstrbot
              ? 'default'
              : (isDeepseek ? 'deepseek-chat' : 'default'))
          : _model.text.trim(),
      systemPrompt: state.config.systemPrompt.isEmpty
          ? BotConfig.defaultPrompt
          : state.config.systemPrompt,
    ));
    await state.setOnboarded();
  }

  void _next() {
    if (_index < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_index > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppState>().theme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.background,
              theme.backgroundSecondary ?? theme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '把大肥鱼接回家',
                  style: TextStyle(
                    color: theme.chromeText,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '三步就能开始聊天：认识你、认识它、接上模型。',
                  style: TextStyle(
                    color: theme.chromeText.withOpacity(0.62),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _stepWrapper(
                        theme: theme,
                        title: '先介绍一下你自己',
                        child: Column(
                          children: [
                            _avatarPicker(
                              theme: theme,
                              path: _myAvatar,
                              name: _myName.text.isEmpty ? '我' : _myName.text,
                              accent: theme.accent,
                              onTap: () => _pickAvatar(mine: true),
                            ),
                            const SizedBox(height: 22),
                            _field(
                              theme: theme,
                              controller: _myName,
                              label: '我的昵称',
                              hint: '比如：小鱼干',
                            ),
                            const SizedBox(height: 14),
                            _field(
                              theme: theme,
                              controller: _signature,
                              label: '个性签名（可跳过）',
                              hint: '写一句此刻的心情',
                            ),
                          ],
                        ),
                      ),
                      _stepWrapper(
                        theme: theme,
                        title: '再认识一下大肥鱼',
                        child: Column(
                          children: [
                            _avatarPicker(
                              theme: theme,
                              path: _botAvatar,
                              name: _botName.text.isEmpty ? '大肥鱼' : _botName.text,
                              accent: theme.accent,
                              onTap: () => _pickAvatar(mine: false),
                            ),
                            const SizedBox(height: 22),
                            _field(
                              theme: theme,
                              controller: _botName,
                              label: '它的名字',
                              hint: '大肥鱼',
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '头像和名字都可以在「设置 → 资料」里随时更换。',
                              style: TextStyle(
                                color: theme.chromeText.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _stepWrapper(
                        theme: theme,
                        title: '接上模型',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '先选一种接入方式。不确定就点右边「怎么接入」，'
                              '里面写了从注册到拿到连接信息的完整步骤。',
                              style: TextStyle(
                                color: theme.chromeText.withOpacity(0.55),
                                fontSize: 11.5,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ConnectionGuideList(
                              theme: theme,
                              compact: true,
                              onApply: (kind) {
                                final info = ConnectionKindInfo.of(kind);
                                setState(() {
                                  _baseUrl.text = info.presetBaseUrl ?? '';
                                  _model.text = info.presetModel ?? '';
                                  _pickedProtocol =
                                      kind == ConnectionKind.astrbot ||
                                              kind == ConnectionKind.phone
                                          ? BotProtocol.astrbot
                                          : BotProtocol.openai;
                                  _testMessage = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _field(
                              theme: theme,
                              controller: _baseUrl,
                              label: 'Base URL',
                              hint: 'https://api.deepseek.com/v1',
                            ),
                            const SizedBox(height: 12),
                            _field(
                              theme: theme,
                              controller: _apiKey,
                              label: 'API Key',
                              hint: 'sk-...',
                              obscure: true,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              theme: theme,
                              controller: _model,
                              label: '模型名',
                              hint: 'deepseek-chat',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _testing ? null : _test,
                                  icon: _testing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.bolt_rounded, size: 18),
                                  label: const Text('测试连接'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Key 只保存在本机，不会上传到任何服务器。',
                                    style: TextStyle(
                                      color: theme.chromeText.withOpacity(0.5),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_testMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: (_testOk ? Colors.green : Colors.red)
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _testMessage!,
                                  style: TextStyle(
                                    color: _testOk
                                        ? const Color(0xFF3CCB7F)
                                        : const Color(0xFFEA5455),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              '填好后点「测试连接」，返回「连通」就说明接上了。'
                              '之后在「设置 → 接入」里也能重新查看这些方法。',
                              style: TextStyle(
                                color: theme.chromeText.withOpacity(0.5),
                                fontSize: 11,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (int i = 0; i < 3; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 6),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? theme.accent
                              : theme.chromeText.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const Spacer(),
                    if (_index > 0)
                      TextButton(
                        onPressed: _back,
                        child: Text(
                          '上一步',
                          style: TextStyle(color: theme.chromeText.withOpacity(0.7)),
                        ),
                      ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _testing
                          ? null
                          : (_index == 2 ? _finish : _next),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 12),
                      ),
                      child: Text(_index == 2 ? '开始聊天' : '下一步'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepWrapper({
    required ChatTheme theme,
    required String title,
    required Widget child,
  }) {
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: theme.isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.chromeText.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: theme.chromeText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _avatarPicker({
    required ChatTheme theme,
    required String? path,
    required String name,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            AvatarView(
              path: path,
              name: name,
              size: 88,
              borderColor: accent.withOpacity(0.7),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required ChatTheme theme,
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: theme.chromeText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: theme.chromeText.withOpacity(0.7)),
        hintStyle: TextStyle(color: theme.chromeText.withOpacity(0.35)),
        filled: true,
        fillColor: theme.isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
