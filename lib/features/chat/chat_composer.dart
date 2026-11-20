import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../models/chat_theme.dart';
import '../../state/app_state.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key, required this.theme});

  final ChatTheme theme;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  /// 选中但还没发送的图片，发送时和输入框里的文字一起发出去
  String? _pendingImagePath;

  /// 录音相关：按住麦克风开始，松手结束并发送（最长 60 秒）
  AudioRecorder? _recorder;
  bool _recording = false;
  bool _pressing = false;
  bool _transcribing = false;
  int _recordSeconds = 0;
  DateTime? _recordStartedAt;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder?.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _startRecord() async {
    if (_recording) return;
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        if (mounted) _toast('没有麦克风权限，请在系统设置里允许「小渔窝」使用麦克风');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}'
          'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordSeconds = 0;
        _recordStartedAt = DateTime.now();
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordSeconds++);
        if (_recordSeconds >= 60) _stopRecord();
      });
      // 手指在启动过程中就松开了：直接丢掉这段录音
      if (!_pressing) await _stopRecord(cancel: true);
    } catch (e) {
      if (mounted) _toast('麦克风打不开：$e');
    }
  }

  Future<void> _stopRecord({bool cancel = false}) async {
    if (!_recording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    final startedAt = _recordStartedAt;
    final recorder = _recorder;
    String? path;
    try {
      path = await recorder?.stop();
    } catch (_) {
      // 停止失败也回到未录音状态
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordSeconds = 0;
      _recordStartedAt = null;
    });

    final durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;
    if (path == null || cancel || durationMs < 800) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // 临时文件删不掉也没关系
        }
      }
      if (!cancel && mounted) _toast('说话时间太短啦');
      return;
    }
    if (!mounted) return;
    // 识别期间显示一条「正在识别」，识别完语音和转写会一起发出去
    setState(() => _transcribing = true);
    try {
      await context.read<AppState>().sendVoice(path, durationMs);
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  Future<void> _send() async {
    final text = _controller.text;
    final imagePath = _pendingImagePath;
    if (text.trim().isEmpty && imagePath == null) return;
    _controller.clear();
    if (imagePath != null) setState(() => _pendingImagePath = null);
    // 不等待整轮回复结束，避免输入框被阻塞
    context.read<AppState>().sendRichMessage(text, imagePath);
    _focus.requestFocus();
  }

  Future<void> _pickImage() async {
    final state = context.read<AppState>();
    final saved = await state.mediaStore.pickImage('images');
    if (saved == null || !mounted) return;
    // 先挂在输入框上方预览，可以和文字一起发送，也可以单独发送
    setState(() => _pendingImagePath = saved);
    _focus.requestFocus();
  }

  Future<void> _showStickers() async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          widget.theme.isDark ? const Color(0xFF161A20) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '表情包',
                      style: TextStyle(
                        color: widget.theme.chromeText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final raw =
                            await state.mediaStore.pickRawImage(maxWidth: 800);
                        if (raw == null) return;
                        await state.importSticker(raw);
                        if (sheetContext.mounted)
                          Navigator.of(sheetContext).pop();
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 18),
                      label: const Text('导入'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (state.stickers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text(
                        '还没有表情包，点右上角「导入」添加本地图片',
                        style: TextStyle(
                          color: widget.theme.chromeText.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: state.stickers.length,
                      itemBuilder: (_, index) {
                        final path = state.stickers[index];
                        return InkWell(
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await state.sendSticker(path);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(path), fit: BoxFit.cover),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final fieldColor = theme.isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.9);
    final canSend = _hasText || _pendingImagePath != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        // 输入栏改成近乎不透明：去掉实时模糊，滚动时更省 GPU
        color: theme.isDark
            ? const Color(0xFF14181F).withOpacity(0.96)
            : Colors.white.withOpacity(0.96),
        border: Border(
          top: BorderSide(
            color: theme.isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImagePath != null) _pendingImageBar(),
          if (_recording || _transcribing) _recordingBar(theme),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _iconButton(
                icon: Icons.emoji_emotions_outlined,
                onTap: _showStickers,
                theme: theme,
              ),
              _iconButton(
                icon: Icons.image_outlined,
                onTap: _pickImage,
                theme: theme,
              ),
              _holdToTalkButton(theme),
              Expanded(
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 42, maxHeight: 120),
                  decoration: BoxDecoration(
                    color: fieldColor,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(color: theme.chromeText, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: '和大肥鱼说点什么…',
                      hintStyle: TextStyle(
                        color: theme.chromeText.withOpacity(0.35),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: canSend ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: canSend
                        ? theme.accent
                        : theme.accent.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 待发送图片的预览条：可以配文字一起发，也可以点右上角删掉。
  Widget _pendingImageBar() {
    final path = _pendingImagePath;
    if (path == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                width: 78,
                height: 78,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 78,
                  height: 78,
                  color: Colors.black.withOpacity(0.15),
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.white70, size: 20),
                ),
              ),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: GestureDetector(
                onTap: () => setState(() => _pendingImagePath = null),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 录音/识别时顶在输入框上方的一条提示，松手自动发送。
  Widget _recordingBar(ChatTheme theme) {
    String two(int v) => v.toString().padLeft(2, '0');
    final seconds = _recordSeconds.clamp(0, 60);
    if (_transcribing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '正在识别语音…',
                style: TextStyle(
                  color: theme.chromeText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEA5455).withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record,
                size: 12, color: Color(0xFFEA5455)),
            const SizedBox(width: 8),
            Text(
              '录音中 ${two(seconds ~/ 60)}:${two(seconds % 60)}',
              style: TextStyle(
                color: theme.chromeText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '松开手指就发送',
                style: TextStyle(
                  color: theme.chromeText.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 按住说话：按下开始录音，松手立即结束并发送。
  Widget _holdToTalkButton(ChatTheme theme) {
    final disabled = _transcribing;
    return Semantics(
      button: true,
      label: '按住说话',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: disabled
            ? null
            : (_) {
                _pressing = true;
                _startRecord();
              },
        onPointerUp: disabled
            ? null
            : (_) {
                _pressing = false;
                _stopRecord();
              },
        onPointerCancel: disabled
            ? null
            : (_) {
                _pressing = false;
                _stopRecord(cancel: true);
              },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            _recording ? Icons.mic_rounded : Icons.mic_none_rounded,
            size: 22,
            color: _recording
                ? const Color(0xFFEA5455)
                : theme.chromeText.withOpacity(disabled ? 0.25 : 0.72),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback? onTap,
    required ChatTheme theme,
    Color? color,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: color ?? theme.chromeText.withOpacity(0.72),
      visualDensity: VisualDensity.compact,
    );
  }
}
