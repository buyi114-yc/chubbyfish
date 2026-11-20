import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_theme.dart';
import '../../state/app_state.dart';

class ThemeEditorPage extends StatefulWidget {
  const ThemeEditorPage({super.key});

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  static const List<int> _palette = [
    0xFFFFFFFF, 0xFFF2F3F5, 0xFFFFF3E0, 0xFFFFE3E9, 0xFFFFD6C9,
    0xFFF6B26B, 0xFFFF8FA8, 0xFFEA5455, 0xFF9B8CFF, 0xFF6D5BD0,
    0xFF2F7CF6, 0xFF4FA3FF, 0xFF3CCB7F, 0xFF1B2B3D, 0xFF23222A, 0xFF0B0B0E,
  ];

  late ChatTheme _draft;

  @override
  void initState() {
    super.initState();
    _draft = context.read<AppState>().theme;
  }

  void _update(ChatTheme value) {
    setState(() => _draft = value.copyWith(id: 'custom', name: '自定义主题'));
  }

  Future<void> _pickImage(String target) async {
    final state = context.read<AppState>();
    final path = await state.mediaStore.pickImage('themes');
    if (path == null || !mounted) return;
    switch (target) {
      case 'bg':
        _update(_draft.copyWith(bgImage: path));
        break;
      case 'userBubble':
        _update(_draft.copyWith(bubbleUserImage: path));
        break;
      case 'botBubble':
        _update(_draft.copyWith(bubbleBotImage: path));
        break;
    }
  }

  Future<void> _save() async {
    await context.read<AppState>().saveTheme(_draft);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _draft;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: theme.chromeText,
        elevation: 0,
        title: const Text('自定义外观'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('保存', style: TextStyle(color: theme.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _preview(theme),
          const SizedBox(height: 20),
          _colorRow(
            theme: theme,
            label: '聊天背景',
            current: theme.bgColor,
            onChanged: (c) => _update(theme.copyWith(bgColor: c)),
          ),
          _colorRow(
            theme: theme,
            label: '我的气泡',
            current: theme.bubbleUserColor,
            onChanged: (c) => _update(theme.copyWith(bubbleUserColor: c)),
          ),
          _colorRow(
            theme: theme,
            label: '对方气泡',
            current: theme.bubbleBotColor,
            onChanged: (c) => _update(theme.copyWith(bubbleBotColor: c)),
          ),
          _colorRow(
            theme: theme,
            label: '我的文字',
            current: theme.userTextColor,
            onChanged: (c) => _update(theme.copyWith(userTextColor: c)),
          ),
          _colorRow(
            theme: theme,
            label: '对方文字',
            current: theme.botTextColor,
            onChanged: (c) => _update(theme.copyWith(botTextColor: c)),
          ),
          _colorRow(
            theme: theme,
            label: '强调色',
            current: theme.accentColor,
            onChanged: (c) =>
                _update(theme.copyWith(accentColor: c, name: '自定义主题')),
          ),
          const SizedBox(height: 8),
          Text('气泡圆角  ${theme.bubbleRadius.toStringAsFixed(0)}',
              style: TextStyle(color: theme.chromeText, fontSize: 12)),
          Slider(
            value: theme.bubbleRadius,
            min: 4,
            max: 28,
            divisions: 24,
            activeColor: theme.accent,
            onChanged: (v) =>
                _update(theme.copyWith(bubbleRadius: v, name: '自定义主题')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('深色界面', style: TextStyle(color: theme.chromeText)),
            value: theme.isDark,
            activeColor: theme.accent,
            onChanged: (v) =>
                _update(theme.copyWith(isDark: v, name: '自定义主题')),
          ),
          const SizedBox(height: 10),
          _imageTile(
            theme: theme,
            label: '聊天背景图',
            path: theme.bgImage,
            onPick: () => _pickImage('bg'),
            onClear: () => _update(theme.copyWith(removeBgImage: true)),
          ),
          _imageTile(
            theme: theme,
            label: '我的气泡背景图',
            path: theme.bubbleUserImage,
            onPick: () => _pickImage('userBubble'),
            onClear: () =>
                _update(theme.copyWith(removeBubbleUserImage: true)),
          ),
          _imageTile(
            theme: theme,
            label: '对方气泡背景图',
            path: theme.bubbleBotImage,
            onPick: () => _pickImage('botBubble'),
            onClear: () =>
                _update(theme.copyWith(removeBubbleBotImage: true)),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('保存主题'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(ChatTheme theme) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.background,
            theme.backgroundSecondary ?? theme.background,
          ],
        ),
        image: theme.bgImage == null
            ? null
            : DecorationImage(
                image: FileImage(File(theme.bgImage!)),
                fit: BoxFit.cover,
                opacity: 0.45,
              ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _bubble(theme, false, '今天也要好好的~'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _bubble(theme, true, '嘿嘿，知道啦'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatTheme theme, bool mine, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? theme.userBubble : theme.botBubble,
        borderRadius: BorderRadius.circular(theme.bubbleRadius),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mine ? theme.userText : theme.botText,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _colorRow({
    required ChatTheme theme,
    required String label,
    required int current,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: theme.chromeText, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette.map((value) {
              final selected = value == current;
              return GestureDetector(
                onTap: () => onChanged(value),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(value),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? theme.accent : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: value > 0x80FFFFFF
                              ? Colors.black87
                              : Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _imageTile({
    required ChatTheme theme,
    required String label,
    required String? path,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: theme.isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.white,
        ),
        clipBehavior: Clip.antiAlias,
        child: path == null
            ? Icon(Icons.image_outlined, color: theme.chromeText.withOpacity(0.5))
            : Image.file(File(path), fit: BoxFit.cover),
      ),
      title: Text(label, style: TextStyle(color: theme.chromeText, fontSize: 13)),
      subtitle: Text(
        path == null ? '未设置' : '已设置',
        style:
            TextStyle(color: theme.chromeText.withOpacity(0.5), fontSize: 10),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null)
            IconButton(
              onPressed: onClear,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: theme.chromeText.withOpacity(0.5)),
            ),
          TextButton(
            onPressed: onPick,
            child: Text('选择', style: TextStyle(color: theme.accent)),
          ),
        ],
      ),
    );
  }
}
