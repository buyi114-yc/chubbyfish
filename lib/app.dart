import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/chat/chat_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'models/chat_theme.dart';
import 'state/app_state.dart';

class ChubbyFishApp extends StatelessWidget {
  const ChubbyFishApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<AppState>().setForeground(state == AppLifecycleState.resumed);
  }

  String _themeKey(ChatTheme theme) => [
        theme.id,
        theme.name,
        theme.bgColor,
        theme.bgColor2,
        theme.bgImage,
        theme.bubbleUserColor,
        theme.bubbleBotColor,
        theme.userTextColor,
        theme.botTextColor,
        theme.bubbleUserImage,
        theme.bubbleBotImage,
        theme.bubbleRadius,
        theme.isDark,
        theme.accentColor,
      ].join('|');

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, state) =>
          '${state.onboarded}|${_themeKey(state.theme)}|${state.user.name}|${state.bot.name}',
      builder: (context, _, __) {
        final state = context.read<AppState>();
        final theme = state.theme;
        return MaterialApp(
          title: '小渔窝',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [chatRouteObserver],
          theme: ThemeData(
            useMaterial3: true,
            brightness: theme.isDark ? Brightness.dark : Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: theme.accent,
              brightness:
                  theme.isDark ? Brightness.dark : Brightness.light,
            ),
            scaffoldBackgroundColor: theme.background,
          ),
          home: state.onboarded
              ? const ChatPage()
              : const OnboardingPage(),
        );
      },
    );
  }
}
