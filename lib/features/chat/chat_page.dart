import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/avatar_view.dart';
import '../moments/moments_page.dart';
import '../settings/settings_page.dart';
import 'chat_composer.dart';
import 'message_bubble.dart';

/// 用来监听「从别的页面回到聊天页」，回来时主动收起键盘
final RouteObserver<PageRoute<dynamic>> chatRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with RouteAware {
  final ScrollController _scroll = ScrollController();
  AppState? _state;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _state!.addListener(_onStateChanged);
    _lastCount = _state!.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    _state?.removeListener(_onStateChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) chatRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // 从设置/动态等页面返回聊天页时，输入框仍可能保留焦点把键盘带出来，
    // 这里统一收掉（延迟一帧，等路由动画把页面恢复完）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = _state!;
    if (state.messages.length != _lastCount) {
      _lastCount = state.messages.length;
      _scrollToBottom();
    } else if (state.isReplying) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // reverse: true 时，offset 0 即为列表底部（最新消息）
      final pos = _scroll.position;
      if (pos.pixels.abs() > 4) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// 以右侧滑入面板的方式展示动态，不另起页面，只占聊天框一部分。
  void _showMomentsPanel() {
    // 先收起键盘，避免面板关掉后焦点回到输入框又把键盘弹出来
    FocusScope.of(context).unfocus();
    // 打开动态即视为已查看：清角标并删掉通知栏里的动态通知
    context.read<AppState>().markMomentsRead();
    showGeneralDialog<void>(
      context: context,
      barrierLabel: '动态',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final state = context.watch<AppState>();
        final theme = state.theme;
        final screenW = MediaQuery.of(context).size.width;
        // 桌面端占 42%，移动端占 88%
        final panelWidth = screenW > 600 ? screenW * 0.42 : screenW * 0.88;
        final curve = Curves.easeOutCubic.transform(animation.value);
        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.black.withOpacity(0.35 * curve)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Transform.translate(
                offset: Offset(panelWidth * (1 - curve), 0),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(22)),
                  child: Container(
                    width: panelWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      // 面板不再实时模糊背景：滚动时每帧重算模糊很吃 GPU
                      color: theme.isDark
                          ? const Color(0xFF14181F).withOpacity(0.99)
                          : const Color(0xFFF5F7FA).withOpacity(0.99),
                      border: Border(
                        left: BorderSide(
                          color: theme.isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ),
                    child: SafeArea(
                      child: MomentsPanel(theme: theme),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  PageRouteBuilder<void> _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        );
        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(opacity: fade, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _choosePresence(AppState state) async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          state.theme.isDark ? const Color(0xFF161A20) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(
              '让大肥鱼知道你的状态',
              style: TextStyle(
                color: state.theme.chromeText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final p in Presence.values)
              ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: p.color, shape: BoxShape.circle),
                ),
                title: Text(
                  p.label,
                  style: TextStyle(color: state.theme.chromeText),
                ),
                trailing: state.presence == p
                    ? Icon(Icons.check_rounded, color: state.theme.accent)
                    : null,
                onTap: () {
                  state.setPresence(p);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = state.theme;

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(theme),
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: _buildHeader(state),
              ),
              Expanded(
                // 点消息列表的空白处也能收起键盘
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: state.messages.isEmpty
                      ? _buildEmpty(state)
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            // reverse: true 使 index 0 在底部；用倒序列表让最新消息在底部
                            final list = state.messages;
                            final msgIndex = list.length - 1 - index;
                            final message = list[msgIndex];
                            // 时间簇：与下一条（更新的）消息间隔超过 5 分钟，或本身是最新一条，则显示时间
                            final showTime = index == 0 ||
                                (msgIndex + 1 < list.length &&
                                    (message.createdAt -
                                                list[msgIndex + 1].createdAt)
                                            .abs() >
                                        5 * 60 * 1000);
                            return MessageBubble(
                              message: message,
                              theme: theme,
                              userName: state.user.name,
                              botName: state.bot.name,
                              userAvatar: state.user.avatarPath,
                              botAvatar: state.bot.avatarPath,
                              showTime: showTime,
                            );
                          },
                        ),
                ),
              ),
              SafeArea(
                top: false,
                child: ChatComposer(theme: theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(ChatTheme theme) {
    final hasImage = theme.bgImage != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImage)
          Image.file(
            File(theme.bgImage!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.background.withOpacity(hasImage ? 0.8 : 1.0),
                (theme.backgroundSecondary ?? theme.background)
                    .withOpacity(hasImage ? 0.8 : 1.0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(AppState state) {
    final theme = state.theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        // 顶部栏近乎不透明：滚动时不再每帧重算模糊，帧率更稳
        color: theme.isDark
            ? const Color(0xFF14181F).withOpacity(0.94)
            : Colors.white.withOpacity(0.94),
        border: Border(
          bottom: BorderSide(
            color: theme.isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _choosePresence(state),
            child: Stack(
              children: [
                AvatarView(
                  path: state.bot.avatarPath,
                  name: state.bot.name,
                  size: 40,
                  borderColor: theme.accent.withOpacity(0.55),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: state.presence.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.background,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _choosePresence(state),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.bot.name,
                    style: TextStyle(
                      color: theme.chromeText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.bot.signature.isNotEmpty
                        ? '${state.presence.label} · ${state.bot.signature}'
                        : '${state.presence.label} · 点此切换状态',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.chromeText.withOpacity(0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '动态',
            onPressed: () => _showMomentsPanel(),
            icon: Badge(
              isLabelVisible: state.unreadMoments > 0,
              label: Text(
                state.unreadMoments > 99 ? '99+' : '${state.unreadMoments}',
              ),
              child: Icon(
                Icons.dynamic_feed_outlined,
                color: theme.chromeText.withOpacity(0.8),
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () {
              // 进设置页前先收起键盘，返回聊天页时就不会自动弹出
              FocusScope.of(context).unfocus();
              Navigator.of(context).push(_slideRoute(
                const SettingsPage(),
              ));
            },
            icon: Icon(
              Icons.settings_rounded,
              color: theme.chromeText.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppState state) {
    final theme = state.theme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarView(
            path: state.bot.avatarPath,
            name: state.bot.name,
            size: 84,
            borderColor: theme.accent.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '${state.bot.name} 已经在等你了',
            style: TextStyle(
              color: theme.chromeText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '说点什么吧，它会记得你说过的话。',
            style: TextStyle(
              color: theme.chromeText.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
