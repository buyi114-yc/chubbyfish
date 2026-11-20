import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/bot_config.dart';
import '../../models/chat_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/avatar_view.dart';
import 'connection_guide.dart';
import 'theme_editor_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _myName;
  late final TextEditingController _signature;
  late final TextEditingController _botName;
  late final TextEditingController _botSignature;
  late final TextEditingController _baseUrl;
  late final TextEditingController _altUrls;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _prompt;
  late final TextEditingController _label;
  late final TextEditingController _astrbotUser;

  double _temp = 0.8;
  BotProtocol _protocol = BotProtocol.openai;
  int _loadedIndex = -1;

  bool _saving = false;
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _myName = TextEditingController(text: s.user.name);
    _signature = TextEditingController(text: s.user.signature);
    _botName = TextEditingController(text: s.bot.name);
    _botSignature = TextEditingController(text: s.bot.signature);
    _baseUrl = TextEditingController(text: s.config.baseUrl);
    _altUrls = TextEditingController(text: s.config.altBaseUrls.join('\n'));
    _apiKey = TextEditingController(text: s.config.apiKey);
    _model = TextEditingController(text: s.config.model);
    _prompt = TextEditingController(text: s.config.systemPrompt);
    _label = TextEditingController(text: s.config.label);
    _astrbotUser = TextEditingController(text: s.config.username);
    _temp = s.config.temperature;
    _protocol = s.config.protocol;
    _loadedIndex = s.activeIndex;
  }

  @override
  void dispose() {
    _myName.dispose();
    _signature.dispose();
    _botName.dispose();
    _botSignature.dispose();
    _baseUrl.dispose();
    _altUrls.dispose();
    _apiKey.dispose();
    _model.dispose();
    _prompt.dispose();
    _label.dispose();
    _astrbotUser.dispose();
    super.dispose();
  }

  /// 切换连接后把输入框同步成当前连接的内容
  void _syncControllers(AppState state) {
    if (_loadedIndex == state.activeIndex) return;
    _loadedIndex = state.activeIndex;
    final config = state.config;
    _label.text = config.label;
    _baseUrl.text = config.baseUrl;
    _altUrls.text = config.altBaseUrls.join('\n');
    _apiKey.text = config.apiKey;
    _model.text = config.model;
    _prompt.text = config.systemPrompt;
    _astrbotUser.text = config.username;
    _temp = config.temperature;
    _protocol = config.protocol;
    _testMessage = null;
  }

  Future<void> _pickAvatar({required bool mine}) async {
    final state = context.read<AppState>();
    final path = await state.mediaStore.pickImage('avatars', maxWidth: 512);
    if (!mounted || path == null) return;
    if (mine) {
      await state.saveUser(state.user.copyWith(avatarPath: path));
    } else {
      await state.saveBot(state.bot.copyWith(avatarPath: path));
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final state = context.read<AppState>();
    await state.saveUser(state.user.copyWith(
      name: _myName.text.trim().isEmpty ? '我' : _myName.text.trim(),
      signature: _signature.text.trim(),
    ));
    await state.saveBot(state.bot.copyWith(
      name: _botName.text.trim().isEmpty ? '大肥鱼' : _botName.text.trim(),
      signature: _botSignature.text.trim(),
    ));
    setState(() => _saving = false);
    if (mounted) _toast('资料已保存');
  }

  Future<void> _saveConfig({bool showToast = true}) async {
    final state = context.read<AppState>();
    final current = state.config;
    final baseUrl = _baseUrl.text.trim();
    final model = _model.text.trim();
    await state.saveConfig(current.copyWith(
      label: _label.text.trim().isEmpty ? current.label : _label.text.trim(),
      baseUrl: baseUrl.isEmpty ? current.baseUrl : baseUrl,
      apiKey: _apiKey.text.trim(),
      model: model.isEmpty ? current.model : model,
      systemPrompt:
          _prompt.text.trim().isEmpty ? BotConfig.defaultPrompt : _prompt.text,
      temperature: _temp,
      protocol: _protocol,
      username: _astrbotUser.text.trim(),
      altBaseUrls: _altUrls.text
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    ));
    if (showToast && mounted) _toast('接入配置已保存');
  }

  Future<void> _test() async {
    await _saveConfig(showToast: false);
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final reply = await context.read<AppState>().testConnection();
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

  Future<void> _selectConnection(int index) async {
    final state = context.read<AppState>();
    if (state.activeIndex == index) return;
    await state.setActiveConnection(index);
    if (!mounted) return;
    _syncControllers(state);
    setState(() {});
  }

  Future<void> _addConnection(BotConfigKind kind) async {
    final state = context.read<AppState>();
    final config = BotConfig.ofKind(kind);
    await state.addConnection(config);
    if (!mounted) return;
    _syncControllers(state);
    setState(() {});
    _toast('已添加「${config.label}」，可直接使用');
  }

  Future<void> _deleteConnection() async {
    final state = context.read<AppState>();
    if (state.connections.length <= 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条连接？'),
        content: Text('「${state.config.label}」将从本机移除，聊天记录不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await state.removeConnection(state.activeIndex);
    if (!mounted) return;
    // 删除后即使下标没变，指向的也可能是另一条连接，强制重新同步
    _loadedIndex = -1;
    _syncControllers(state);
    setState(() {});
  }

  void _showAddSheet(ChatTheme theme) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.isDark ? const Color(0xFF1B2028) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '新增连接',
                style: TextStyle(
                  color: theme.chromeText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final kind in BotConfigKind.values)
              ListTile(
                leading: Icon(_kindIcon(kind), color: theme.accent),
                title: Text(
                  kind.label,
                  style: TextStyle(color: theme.chromeText, fontSize: 14),
                ),
                subtitle: Text(
                  kind.description,
                  style: TextStyle(
                    color: theme.chromeText.withOpacity(0.55),
                    fontSize: 11,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _addConnection(kind);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _protocolOption(ChatTheme theme, BotProtocol protocol) {
    final selected = _protocol == protocol;
    return GestureDetector(
      onTap: () => setState(() {
        _protocol = protocol;
        _testMessage = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? theme.accent.withValues(alpha: 0.14)
              : (theme.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.accent
                : theme.chromeText.withValues(alpha: 0.12),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              protocol.label,
              style: TextStyle(
                color: selected ? theme.accent : theme.chromeText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              protocol.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.chromeText.withValues(alpha: 0.5),
                fontSize: 9.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(BotConfigKind kind) => switch (kind) {
        BotConfigKind.deepseek => Icons.bolt_rounded,
        BotConfigKind.astrbot => Icons.hub_rounded,
        BotConfigKind.custom => Icons.tune_rounded,
      };

  void _showHelp() {
    final theme = context.read<AppState>().theme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '怎么接入',
                style: TextStyle(
                  color: theme.chromeText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '三种方式任选一种。点每一项右边的「怎么接入」，'
                '可以看从注册到拿到连接信息的完整步骤。',
                style: TextStyle(
                  color: theme.chromeText.withOpacity(0.55),
                  fontSize: 11.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              ConnectionGuideList(theme: theme),
              const SizedBox(height: 14),
              Text(
                '两条连接可以同时保存，点卡片即可切换，切换后下一条消息立即生效。',
                style: TextStyle(
                  color: theme.chromeText.withOpacity(0.45),
                  fontSize: 10.5,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 从剪贴板一键粘贴 Key。
  ///
  /// API Key 输入框不再使用 obscureText，避免部分 Android ROM 强制切换成
  /// 系统安全键盘、从而禁止长按粘贴。
  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) _toast('剪贴板里没有可粘贴的文字');
      return;
    }
    _apiKey.text = text;
    _apiKey.selection = TextSelection.collapsed(offset: text.length);
    if (mounted) _toast('已粘贴 Key');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = state.theme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: theme.chromeText,
          elevation: 0,
          title: const Text('设置'),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: theme.isDark
                    ? Colors.black.withOpacity(0.18)
                    : Colors.white.withOpacity(0.4),
              ),
            ),
          ),
          bottom: TabBar(
            indicatorColor: theme.accent,
            indicatorWeight: 2.5,
            labelColor: theme.chromeText,
            unselectedLabelColor: theme.chromeText.withOpacity(0.5),
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            tabs: [
              Tab(
                icon: _ovalTab(theme, '外观', Colors.purple,
                    Icons.palette_outlined),
              ),
              Tab(
                icon: _ovalTab(theme, '资料', Colors.teal,
                    Icons.person_outline_rounded),
              ),
              Tab(
                icon: _ovalTab(theme, '接入', Colors.blue,
                    Icons.settings_ethernet_rounded),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 48),
              child: _appearanceTab(state, theme),
            ),
            Padding(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 48),
              child: _profileTab(state, theme),
            ),
            Padding(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 48),
              child: _connectTab(state, theme),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 外观 ----------------

  Widget _appearanceTab(AppState state, ChatTheme theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        _sectionTitle('预设主题', theme),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = state.presets[index];
              final selected = state.theme.id == preset.id;
              return GestureDetector(
                onTap: () => state.applyPreset(preset),
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? theme.accent
                          : theme.chromeText.withOpacity(0.12),
                      width: selected ? 2 : 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        preset.background,
                        preset.backgroundSecondary ?? preset.background,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: preset.userBubble,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '嗨',
                          style:
                              TextStyle(color: preset.userText, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        preset.name,
                        style: TextStyle(
                          color: preset.chromeText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
        _sectionTitle('自定义', theme),
        _card(
          theme: theme,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(Icons.tune_rounded, theme),
              title: Text('气泡 / 文字 / 背景',
                  style: TextStyle(color: theme.chromeText, fontSize: 14)),
              subtitle: Text(
                '当前：${state.theme.name}',
                style: TextStyle(
                    color: theme.chromeText.withOpacity(0.5), fontSize: 11),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: theme.chromeText.withOpacity(0.5)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ThemeEditorPage()),
              ),
            ),
            Divider(color: theme.chromeText.withOpacity(0.08)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(Icons.restart_alt_rounded, theme),
              title: Text('恢复默认主题',
                  style: TextStyle(color: theme.chromeText, fontSize: 14)),
              onTap: () => state.applyPreset(state.presets.first),
            ),
            Divider(color: theme.chromeText.withOpacity(0.08)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(Icons.font_download_rounded, theme,
                  color: Colors.deepPurple),
              title: Text('聊天字体',
                  style: TextStyle(color: theme.chromeText, fontSize: 14)),
              subtitle: Text(
                state.theme.fontFamily ?? '默认',
                style: TextStyle(
                    color: theme.chromeText.withOpacity(0.5), fontSize: 11),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: theme.chromeText.withOpacity(0.5)),
              onTap: () => _pickFont(state, theme),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickFont(AppState state, ChatTheme theme) async {
    final current = state.theme.fontFamily ?? '默认';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.isDark ? const Color(0xFF1B2028) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: ChatTheme.fontFamilies.length,
          separatorBuilder: (_, __) =>
              Divider(color: theme.chromeText.withOpacity(0.06), height: 1),
          itemBuilder: (context, index) {
            final font = ChatTheme.fontFamilies[index];
            final selected = font == current;
            return ListTile(
              title: Text(
                font,
                style: TextStyle(
                  color: selected ? theme.accent : theme.chromeText,
                  fontFamily: font == '默认' ? null : font,
                  fontSize: 15,
                ),
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: theme.accent)
                  : null,
              onTap: () async {
                await state.saveTheme(state.theme.copyWith(
                  fontFamily: font == '默认' ? null : font,
                ));
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              },
            );
          },
        ),
      ),
    );
  }

  // ---------------- 资料 ----------------

  void _showSignatureHistory(AppState state, ChatTheme theme) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.isDark ? const Color(0xFF1B2028) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final history = state.signatureHistory;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '大肥鱼的签名历史',
                  style: TextStyle(
                    color: theme.chromeText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '还没有历史签名～',
                    style: TextStyle(
                        color: theme.chromeText.withOpacity(0.5),
                        fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, __) => Divider(
                        color: theme.chromeText.withOpacity(0.06),
                        height: 1),
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final sig = item['signature'] as String? ?? '';
                      final ts = item['timestamp'] as int? ?? 0;
                      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
                      String two(int v) => v.toString().padLeft(2, '0');
                      final label =
                          '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
                      return ListTile(
                        title: Text(
                          sig,
                          style: TextStyle(
                              color: theme.chromeText, fontSize: 14),
                        ),
                        subtitle: Text(
                          label,
                          style: TextStyle(
                              color: theme.chromeText.withOpacity(0.4),
                              fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _profileTab(AppState state, ChatTheme theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _avatarBlock(
              theme: theme,
              label: '我的头像',
              path: state.user.avatarPath,
              name: state.user.name,
              onTap: () => _pickAvatar(mine: true),
            ),
            _avatarBlock(
              theme: theme,
              label: '大肥鱼头像',
              path: state.bot.avatarPath,
              name: state.bot.name,
              onTap: () => _pickAvatar(mine: false),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _field(theme, _myName, '我的昵称'),
        const SizedBox(height: 12),
        _field(theme, _signature, '个性签名'),
        const SizedBox(height: 12),
        _field(theme, _botName, '大肥鱼的名字'),
        const SizedBox(height: 12),
        _field(theme, _botSignature, '大肥鱼的签名（她也可能自己改）'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _showSignatureHistory(state, theme),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _iconBox(Icons.history_rounded, theme, color: Colors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '历史签名（${state.signatureHistory.length}）',
                    style: TextStyle(
                        color: theme.chromeText, fontSize: 13.5),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: theme.chromeText.withOpacity(0.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('我的在线状态', style: _labelStyle(theme)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Presence>(
              value: state.presence,
              isExpanded: true,
              dropdownColor:
                  theme.isDark ? const Color(0xFF1B2028) : Colors.white,
              items: Presence.values
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: p.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(p.label,
                                style: TextStyle(
                                    color: theme.chromeText, fontSize: 13)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (p) {
                if (p != null) state.setPresence(p);
              },
            ),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: _glassButton(
            theme: theme,
            label: '保存资料',
            icon: Icons.check_rounded,
            primary: true,
            loading: _saving,
            onPressed: _saving ? null : _saveProfile,
          ),
        ),
      ],
    );
  }

  // ---------------- 接入 ----------------

  Widget _avatarBlock({
    required ChatTheme theme,
    required String label,
    required String? path,
    required String name,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            children: [
              AvatarView(
                path: path,
                name: name,
                size: 72,
                borderColor: theme.accent.withOpacity(0.5),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: theme.chromeText.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ---------------- 接入 ----------------

  Widget _connectTab(AppState state, ChatTheme theme) {
    _syncControllers(state);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'DeepSeek 直连和 AstrBot 都能保存，点卡片即可切换，'
                '下一条消息立即走新连接。',
                style: TextStyle(
                  color: theme.chromeText.withValues(alpha: 0.55),
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
            ),
            TextButton(
              onPressed: _showHelp,
              child: Text(
                '接入帮助',
                style: TextStyle(color: theme.accent, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < state.connections.length; i++)
          _connectionCard(state, theme, i, state.connections[i]),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _glassButton(
                theme: theme,
                label: '新增连接',
                icon: Icons.add_rounded,
                onPressed: () => _showAddSheet(theme),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _glassButton(
                theme: theme,
                label: '删除当前',
                icon: Icons.delete_outline_rounded,
                onPressed:
                    state.connections.length <= 1 ? null : _deleteConnection,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle('当前连接设置', theme),
        const SizedBox(height: 10),
        _sectionTitle('接口协议', theme),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final p in BotProtocol.values) ...[
              Expanded(child: _protocolOption(theme, p)),
              if (p != BotProtocol.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _field(theme, _label, '连接名称'),
        const SizedBox(height: 12),
        _field(
          theme,
          _baseUrl,
          _protocol == BotProtocol.astrbot ? 'AstrBot 面板地址' : 'Base URL',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _field(
          theme,
          _apiKey,
          _protocol == BotProtocol.astrbot
              ? 'OpenAPI Key（abk_ 开头）'
              : 'API Key',
          suffix: IconButton(
            tooltip: '从剪贴板粘贴',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.content_paste_rounded,
              size: 18,
              color: theme.chromeText.withOpacity(0.7),
            ),
            onPressed: _pasteApiKey,
          ),
        ),
        if (_protocol == BotProtocol.astrbot) ...[
          const SizedBox(height: 12),
          _field(
            theme,
            _altUrls,
            '备用地址（每行一个，按顺序尝试）',
            maxLines: 3,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 6),
          Text(
            '主地址优先，不通时自动切到下面的备用地址。建议主地址填局域网，'
            '备用地址填 Tailscale，这样在家走局域网、在外面自动走 Tailscale。',
            style: TextStyle(
              color: theme.chromeText.withValues(alpha: 0.5),
              fontSize: 11,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          _field(theme, _astrbotUser, '用户名（留空使用我的昵称）'),
          const SizedBox(height: 10),
          Text(
            'AstrBot 会用它自己在面板里配置的模型和人格，这里的模型名、温度、'
            'System Prompt 不生效。手机端请把地址改成电脑的局域网 IP。',
            style: TextStyle(
              color: theme.chromeText.withValues(alpha: 0.5),
              fontSize: 11,
              height: 1.55,
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          _field(theme, _model, '模型名'),
          const SizedBox(height: 16),
          Text('温度 ${_temp.toStringAsFixed(2)}', style: _labelStyle(theme)),
          Slider(
            value: _temp,
            min: 0,
            max: 1.5,
            divisions: 15,
            activeColor: theme.accent,
            onChanged: (v) => setState(() => _temp = v),
          ),
          const SizedBox(height: 6),
          _field(theme, _prompt, '人格设定（System Prompt）', maxLines: 6),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _glassButton(
                theme: theme,
                label: '保存配置',
                icon: Icons.save_rounded,
                primary: true,
                onPressed: () => _saveConfig(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _glassButton(
                theme: theme,
                label: '测试连接',
                icon: Icons.bolt_rounded,
                loading: _testing,
                onPressed: _testing ? null : _test,
              ),
            ),
          ],
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_testOk ? Colors.green : Colors.red).withOpacity(0.12),
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
        const SizedBox(height: 26),
        _card(
          theme: theme,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(Icons.delete_sweep_outlined, theme,
                  color: Colors.orange),
              title: Text('清空聊天记录',
                  style: TextStyle(color: theme.chromeText, fontSize: 14)),
              onTap: () => state.clearHistory(),
            ),
            Divider(color: theme.chromeText.withOpacity(0.08)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _iconBox(Icons.info_outline_rounded, theme,
                  color: Colors.teal),
              title: Text('小渔窝 v0.1.0',
                  style: TextStyle(color: theme.chromeText, fontSize: 14)),
              subtitle: Text(
                '本地优先 · 后续支持多端同步',
                style: TextStyle(
                    color: theme.chromeText.withOpacity(0.5), fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectionCard(
    AppState state,
    ChatTheme theme,
    int index,
    BotConfig config,
  ) {
    final active = index == state.activeIndex;
    return GestureDetector(
      onTap: () => _selectConnection(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.isDark
              ? Colors.white.withValues(alpha: active ? 0.1 : 0.04)
              : Colors.white.withValues(alpha: active ? 0.95 : 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? theme.accent
                : theme.chromeText.withValues(alpha: 0.12),
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _kindIcon(config.kind),
              size: 20,
              color: active
                  ? theme.accent
                  : theme.chromeText.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.label,
                    style: TextStyle(
                      color: theme.chromeText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    config.protocol == BotProtocol.astrbot
                        ? '${config.displayTarget} · OpenAPI'
                        : '${config.displayTarget} · ${config.model}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.chromeText.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '使用中',
                  style: TextStyle(color: theme.accent, fontSize: 10.5),
                ),
              )
            else
              Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: theme.chromeText.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- 通用小组件 ----------------

  Widget _sectionTitle(String text, ChatTheme theme) => Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: theme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: theme.chromeText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  TextStyle _labelStyle(ChatTheme theme) => TextStyle(
        color: theme.chromeText.withOpacity(0.7),
        fontSize: 12,
      );

  /// 毛玻璃卡片：半透明背景 + 模糊 + 细边框。
  Widget _card({required ChatTheme theme, required List<Widget> children}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: theme.isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.6),
              ),
            ),
            child: Column(children: children),
          ),
        ),
      );

  /// 带圆角背景的小图标，让列表项更精致。
  Widget _iconBox(IconData icon, ChatTheme theme, {Color? color}) =>
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: (color ?? theme.accent).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color ?? theme.accent),
      );

  /// 椭圆形 Tab：图标+文字都在椭圆底色内，不会遮挡下方内容。
  Widget _ovalTab(ChatTheme theme, String label, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  /// 毛玻璃按钮：带按压反馈。
  Widget _glassButton({
    required ChatTheme theme,
    required String label,
    IconData? icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool loading = false,
  }) {
    final bg = primary
        ? theme.accent.withOpacity(0.85)
        : (theme.isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.45));
    final fg = primary ? Colors.white : theme.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: bg,
          child: InkWell(
            onTap: onPressed,
            splashColor: fg.withOpacity(0.15),
            highlightColor: fg.withOpacity(0.08),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primary
                      ? theme.accent.withOpacity(0.5)
                      : (theme.isDark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.white.withOpacity(0.7)),
                ),
              ),
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18, color: fg),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            label,
                            style: TextStyle(
                              color: fg,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    ChatTheme theme,
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.chromeText, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        labelStyle: TextStyle(
            color: theme.chromeText.withOpacity(0.6), fontSize: 12),
        filled: true,
        fillColor: theme.isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      ),
    );
  }
}
