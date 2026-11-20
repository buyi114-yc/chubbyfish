import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils.dart';
import '../../models/chat_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../state/app_state.dart';
import '../../widgets/avatar_view.dart';

class MomentsPage extends StatelessWidget {
  const MomentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = state.theme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: theme.chromeText,
        elevation: 0,
        title: const Text('动态'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.accent,
        foregroundColor: Colors.white,
        onPressed: () => _compose(context),
        child: const Icon(Icons.edit_rounded),
      ),
      body: DefaultTextStyle.merge(
        // 动态里的文字一律不带下划线，避免继承到外面的装饰样式
        style: const TextStyle(decoration: TextDecoration.none),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
          children: [
            _signatureCard(context, state, theme),
            const SizedBox(height: 16),
            if (state.moments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: theme.chromeText.withOpacity(0.35), size: 34),
                    const SizedBox(height: 10),
                    Text(
                      '还没有动态，记录一下此刻吧',
                      style: TextStyle(
                        color: theme.chromeText.withOpacity(0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...state.moments.map(
                (moment) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AvatarView(
                            path: state.user.avatarPath,
                            name: state.user.name,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.user.name,
                              style: TextStyle(
                                color: theme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            relativeTimeLabel(moment.createdAt),
                            style: TextStyle(
                              color: theme.chromeText.withOpacity(0.4),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      if (moment.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          moment.text,
                          style: TextStyle(
                            color: theme.chromeText,
                            fontSize: 14,
                            height: 1.5,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                      if (moment.imagePath != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(moment.imagePath!),
                            width: double.infinity,
                            height: 190,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => state.toggleMomentLike(moment.id),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              moment.liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                              color: moment.liked
                                  ? const Color(0xFFFF7A9C)
                                  : theme.chromeText.withOpacity(0.4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              moment.liked ? '喜欢' : '点赞',
                              style: TextStyle(
                                color: theme.chromeText.withOpacity(0.45),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _signatureCard(BuildContext context, AppState state, ChatTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.backgroundSecondary ?? theme.background,
            theme.background,
          ],
        ),
        border: Border.all(color: theme.chromeText.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          AvatarView(
            path: state.user.avatarPath,
            name: state.user.name,
            size: 52,
            borderColor: theme.accent.withOpacity(0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.user.name,
                  style: TextStyle(
                    color: theme.chromeText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.user.signature.isEmpty
                      ? '还没写个性签名'
                      : state.user.signature,
                  style: TextStyle(
                    color: theme.chromeText.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _editSignature(context, state),
            icon: Icon(Icons.edit_outlined, color: theme.accent, size: 20),
          ),
        ],
      ),
    );
  }

  Future<void> _editSignature(BuildContext context, AppState state) async {
    final controller = TextEditingController(text: state.user.signature);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('个性签名'),
        content: TextField(
          controller: controller,
          maxLength: 60,
          style: const TextStyle(decoration: TextDecoration.none),
          decoration: const InputDecoration(hintText: '写一句此刻的心情'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await state.saveUser(
                state.user.copyWith(signature: controller.text.trim()),
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    final state = context.read<AppState>();
    String text = '';
    String? imagePath;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          state.theme.isDark ? const Color(0xFF161A20) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发一条动态',
                  style: TextStyle(
                      color: state.theme.chromeText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 4,
                  autofocus: true,
                  onChanged: (v) => text = v,
                  style: TextStyle(
                      color: state.theme.chromeText,
                      decoration: TextDecoration.none),
                  decoration: const InputDecoration(
                    hintText: '记录此刻…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (imagePath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(imagePath!),
                        height: 120, fit: BoxFit.cover),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final raw = await state.mediaStore.pickRawImage();
                        if (raw == null) return;
                        setSheet(() => imagePath = raw);
                      },
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('图片'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        if (text.trim().isEmpty && imagePath == null) return;
                        await state.postMoment(text, imagePath);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: state.theme.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('发布'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 动态面板：以右侧叠加面板形式展示，带毛玻璃卡片效果。
class MomentsPanel extends StatelessWidget {
  const MomentsPanel({super.key, required this.theme});

  final ChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return DefaultTextStyle.merge(
      // 动态面板里的文字一律不带下划线
      style: const TextStyle(decoration: TextDecoration.none),
      child: Column(
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  '动态',
                  style: TextStyle(
                    color: theme.chromeText,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _compose(context),
                  icon: Icon(Icons.edit_rounded, color: theme.accent, size: 22),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded,
                      color: theme.chromeText.withOpacity(0.7), size: 22),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              children: [
                _signatureCard(context, state, theme),
                const SizedBox(height: 10),
                _botSignatureCard(context, state, theme),
                const SizedBox(height: 14),
                if (state.moments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            color: theme.chromeText.withOpacity(0.35),
                            size: 34),
                        const SizedBox(height: 10),
                        Text(
                          '还没有动态，记录一下此刻吧',
                          style: TextStyle(
                            color: theme.chromeText.withOpacity(0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...state.moments.map(
                    (moment) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        // 卡片不再逐张做实时模糊：十几层高斯模糊会让滚动明显掉帧
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border(
                            top: BorderSide(
                              color: theme.isDark
                                  ? Colors.white.withOpacity(0.10)
                                  : Colors.white.withOpacity(0.6),
                            ),
                            right: BorderSide(
                              color: theme.isDark
                                  ? Colors.white.withOpacity(0.10)
                                  : Colors.white.withOpacity(0.6),
                            ),
                            bottom: BorderSide(
                              color: theme.isDark
                                  ? Colors.white.withOpacity(0.10)
                                  : Colors.white.withOpacity(0.6),
                            ),
                            // 大肥鱼的动态左侧用主题色竖条，用户动态用中性色
                            left: BorderSide(
                              color: moment.isBot
                                  ? theme.accent
                                  : theme.chromeText.withOpacity(0.25),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AvatarView(
                                  path: moment.isBot
                                      ? state.bot.avatarPath
                                      : state.user.avatarPath,
                                  name: moment.isBot
                                      ? state.bot.name
                                      : state.user.name,
                                  size: 32,
                                  borderColor: moment.isBot
                                      ? theme.accent.withOpacity(0.6)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          moment.isBot
                                              ? state.bot.name
                                              : state.user.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: moment.isBot
                                                ? theme.accent
                                                : theme.chromeText,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // 作者标签
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: moment.isBot
                                              ? theme.accent.withOpacity(0.15)
                                              : theme.chromeText
                                                  .withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          moment.isBot ? '她' : '我',
                                          style: TextStyle(
                                            color: moment.isBot
                                                ? theme.accent
                                                : theme.chromeText
                                                    .withOpacity(0.55),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  relativeTimeLabel(moment.createdAt),
                                  style: TextStyle(
                                    color: theme.chromeText.withOpacity(0.4),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            if (moment.text.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                moment.text,
                                style: TextStyle(
                                  color: theme.chromeText,
                                  fontSize: 14,
                                  height: 1.5,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                            if (moment.imagePath != null) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () =>
                                    showImageViewer(context, moment.imagePath!),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(moment.imagePath!),
                                    width: double.infinity,
                                    height: 170,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => state.toggleMomentLike(moment.id),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    moment.liked
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 16,
                                    color: moment.liked
                                        ? const Color(0xFFFF7A9C)
                                        : theme.chromeText.withOpacity(0.4),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    moment.liked ? '喜欢' : '点赞',
                                    style: TextStyle(
                                      color: theme.chromeText.withOpacity(0.45),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signatureCard(BuildContext context, AppState state, ChatTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.6),
        ),
      ),
      child: Row(
        children: [
          AvatarView(
            path: state.user.avatarPath,
            name: state.user.name,
            size: 48,
            borderColor: theme.accent.withOpacity(0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.user.name,
                  style: TextStyle(
                    color: theme.chromeText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.user.signature.isEmpty
                      ? '还没写个性签名'
                      : state.user.signature,
                  style: TextStyle(
                    color: theme.chromeText.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 大肥鱼的签名卡：accent 色调，与用户签名卡区分。
  Widget _botSignatureCard(
      BuildContext context, AppState state, ChatTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.isDark
            ? theme.accent.withOpacity(0.10)
            : theme.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.accent.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          AvatarView(
            path: state.bot.avatarPath,
            name: state.bot.name,
            size: 48,
            borderColor: theme.accent.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        state.bot.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.chromeText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: theme.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '她',
                        style: TextStyle(
                          color: theme.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.bot.signature.isEmpty ? '她还没写签名' : state.bot.signature,
                  style: TextStyle(
                    color: theme.chromeText.withOpacity(0.55),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    final state = context.read<AppState>();
    String text = '';
    String? imagePath;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          state.theme.isDark ? const Color(0xFF161A20) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发一条动态',
                  style: TextStyle(
                      color: state.theme.chromeText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLines: 4,
                  autofocus: true,
                  onChanged: (v) => text = v,
                  style: TextStyle(
                      color: state.theme.chromeText,
                      decoration: TextDecoration.none),
                  decoration: const InputDecoration(
                    hintText: '记录此刻…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (imagePath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(imagePath!),
                        height: 120, fit: BoxFit.cover),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final raw = await state.mediaStore.pickRawImage();
                        if (raw == null) return;
                        setSheet(() => imagePath = raw);
                      },
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('图片'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        if (text.trim().isEmpty && imagePath == null) return;
                        await state.postMoment(text, imagePath);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: state.theme.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('发布'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
