import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 统一管理用户导入的图片（头像 / 聊天背景 / 气泡背景 / 聊天图片 / 表情包）。
/// 全部复制到应用私有目录，避免系统清理缓存后图片丢失。
class MediaStore {
  Directory? _root;

  Future<Directory> get root async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}chubbyfish');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<Directory> folder(String name) async {
    final base = await root;
    final dir = Directory('${base.path}${Platform.pathSeparator}$name');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> importFile(String sourcePath, String folderName) async {
    final dir = await folder(folderName);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_basename(sourcePath)}';
    final dest = '${dir.path}${Platform.pathSeparator}$name';
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// 从相册/文件选择器挑一张图并保存到指定目录，返回新路径；取消返回 null。
  Future<String?> pickImage(String folderName, {double maxWidth = 1600}) async {
    final raw = await pickRawImage(maxWidth: maxWidth);
    if (raw == null) return null;
    return importFile(raw, folderName);
  }

  /// 只取回临时路径（不复制），用于“导入表情包”等需要自己决定落盘位置的场景。
  Future<String?> pickRawImage({double maxWidth = 1600}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth,
      maxHeight: maxWidth,
      imageQuality: 88,
    );
    return picked?.path;
  }

  /// 直接把字节写入指定目录，用于下载网络图片等场景。
  Future<String> importBytes(
    String folderName,
    List<int> bytes, {
    String extension = 'png',
  }) async {
    final dir = await folder(folderName);
    final name = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final dest = '${dir.path}${Platform.pathSeparator}$name';
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  Future<List<String>> listFiles(String folderName) async {
    final dir = await folder(folderName);
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.map((f) => f.path).toList();
  }

  String _basename(String path) {
    final index = path.lastIndexOf(RegExp(r'[/\\]'));
    return index == -1 ? path : path.substring(index + 1);
  }
}
