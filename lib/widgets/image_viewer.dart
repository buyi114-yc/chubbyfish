import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// 全屏图片查看器：双指缩放、拖拽、点击空白关闭，右上角可保存到相册。
void showImageViewer(BuildContext context, String imagePath) {
  // 收起键盘，返回聊天页时不至于又弹出来
  FocusScope.of(context).unfocus();
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: ImageViewerPage(imagePath: imagePath),
        );
      },
    ),
  );
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _tc = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (!await Gal.hasAccess()) await Gal.requestAccess();
        await Gal.putImage(widget.imagePath);
        messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
      } else {
        final dir = await getDownloadsDirectory() ?? Directory.systemTemp;
        final dot = widget.imagePath.lastIndexOf('.');
        final ext = dot >= 0 ? widget.imagePath.substring(dot) : '.jpg';
        final target = File(
          '${dir.path}${Platform.pathSeparator}'
          'xiaoyuwo_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        await File(widget.imagePath).copy(target.path);
        messenger.showSnackBar(SnackBar(content: Text('已保存到 ${target.path}')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('保存失败，检查相册权限后再试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: _tc,
              minScale: 0.8,
              maxScale: 5.0,
              child: Center(
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _save,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _saving
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 19,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
