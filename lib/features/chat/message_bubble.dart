import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/chat_theme.dart';
import '../../core/utils.dart';
import '../../widgets/avatar_view.dart';
import '../../widgets/image_viewer.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.theme,
    required this.userName,
    required this.botName,
    this.userAvatar,
    this.botAvatar,
    this.showTime = false,
  });

  final ChatMessage message;
  final ChatTheme theme;
  final String userName;
  final String botName;
  final String? userAvatar;
  final String? botAvatar;
  final bool showTime;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 点语音气泡播放/停止，和微信一样的交互。
  Future<void> _togglePlay() async {
    final path = widget.message.mediaPath;
    if (path == null) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      // 文件被清理或格式不支持时静默失败
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = widget.theme;
    final isUser = message.isUser;
    final bubbleColor = isUser ? theme.userBubble : theme.botBubble;
    final textColor = isUser ? theme.userText : theme.botText;
    final bubbleImage = isUser ? theme.bubbleUserImage : theme.bubbleBotImage;

    final content = _buildContent(textColor);
    final bubble = message.kind == MessageKind.sticker
        ? content
        : Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleImage == null ? bubbleColor : null,
              image: bubbleImage == null
                  ? null
                  : DecorationImage(
                      image: FileImage(File(bubbleImage)),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        bubbleColor.withOpacity(0.55),
                        BlendMode.srcOver,
                      ),
                    ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(theme.bubbleRadius),
                topRight: Radius.circular(theme.bubbleRadius),
                bottomLeft: Radius.circular(isUser ? theme.bubbleRadius : 5),
                bottomRight: Radius.circular(isUser ? 5 : theme.bubbleRadius),
              ),
            ),
            child: content,
          );

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                AvatarView(
                    path: widget.botAvatar, name: widget.botName, size: 36),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 用户消息：时间在气泡左边；bot 消息：时间在气泡右边
                        if (isUser && widget.showTime) ...[
                          _timeText(textColor),
                          const SizedBox(width: 6),
                        ],
                        Flexible(child: bubble),
                        if (!isUser && widget.showTime) ...[
                          const SizedBox(width: 6),
                          _timeText(textColor),
                        ],
                      ],
                    ),
                    if (message.status == MessageStatus.sending &&
                        message.text.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _sendingIndicator(textColor),
                    ],
                    if (message.status == MessageStatus.failed) ...[
                      const SizedBox(height: 3),
                      _failedIndicator(),
                    ],
                  ],
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 8),
                AvatarView(
                    path: widget.userAvatar, name: widget.userName, size: 36),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color textColor) {
    final message = widget.message;
    switch (message.kind) {
      case MessageKind.image:
        final path = message.mediaPath;
        final caption = message.text.trim();
        final image = GestureDetector(
          onTap: () {
            if (path != null) {
              showImageViewer(context, path);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: path == null
                ? const SizedBox(width: 120, height: 90)
                : Image.file(
                    File(path),
                    width: 190,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _brokenBox(),
                  ),
          ),
        );
        if (caption.isEmpty) return image;
        // 图文同发：图片下面带上一起发出去的文字
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            image,
            const SizedBox(height: 8),
            Text(
              caption,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
            ),
          ],
        );
      case MessageKind.sticker:
        final path = message.mediaPath;
        return path == null
            ? _brokenBox()
            : Image.file(
                File(path),
                width: 110,
                errorBuilder: (_, __, ___) => _brokenBox(),
              );
      case MessageKind.voice:
        final seconds = ((message.durationMs ?? 0) ~/ 1000).clamp(1, 600);
        final transcript = message.text.trim();
        final bar = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(
              '$seconds"',
              style: TextStyle(color: textColor, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Icon(
              _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18,
              color: textColor,
            ),
          ],
        );
        return GestureDetector(
          onTap: _togglePlay,
          behavior: HitTestBehavior.opaque,
          child: transcript.isEmpty
              ? bar
              // 微信式：语音下面直接给出转写文字
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar,
                    const SizedBox(height: 6),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: textColor.withOpacity(0.12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      transcript,
                      style: TextStyle(
                        color: textColor.withOpacity(0.92),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
        );
      case MessageKind.system:
      case MessageKind.text:
        if (message.text.isEmpty && message.status == MessageStatus.sending) {
          return const _TypingIndicator();
        }
        final fontFamily = widget.theme.fontFamily;
        return SelectableText(
          message.text,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            height: 1.45,
            fontFamily:
                (fontFamily == null || fontFamily == '默认') ? null : fontFamily,
          ),
          cursorColor: textColor,
        );
    }
  }

  Widget _brokenBox() => Container(
        width: 120,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.broken_image_outlined, color: Colors.white70),
      );

  /// 时间标签：显示在气泡旁边。
  Widget _timeText(Color textColor) {
    final message = widget.message;
    final theme = widget.theme;
    final isUser = message.isUser;
    return Text(
      timeLabel(message.createdAt),
      style: TextStyle(
        color: (isUser ? theme.userText : theme.botText).withOpacity(0.5),
        fontSize: 10,
      ),
    );
  }

  /// 发送中指示器。
  Widget _sendingIndicator(Color textColor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: textColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '发送中',
            style: TextStyle(
              color: textColor.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ],
      );

  /// 发送失败指示器。
  Widget _failedIndicator() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 12, color: Color(0xFFEA5455)),
          const SizedBox(width: 4),
          Text(
            '发送失败',
            style: TextStyle(
              color: const Color(0xFFEA5455).withOpacity(0.9),
              fontSize: 10,
            ),
          ),
        ],
      );
}

/// 三个跳动的小圆点，作为「正在输入」指示器。
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 原来这里直接读 _c.value 但没有监听动画，所以只会停在第一帧（看起来只跳一下）；
    // 用 AnimatedBuilder 让三个点真正连续起伏，同时做大小与透明度呼吸。
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        const dotColor = Color(0xFF8FA9C0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = _c.value * 2 * math.pi - i * 0.9;
            final wave = (math.sin(phase) + 1) / 2; // 0..1，平滑正弦
            final size = 5.5 + wave * 2.5;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.4),
              child: Transform.translate(
                offset: Offset(0, -wave * 4.0),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: 0.35 + wave * 0.65),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.10 + wave * 0.20),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
