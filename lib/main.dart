import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_storage.dart';
import 'core/background_sync.dart';
import 'core/media_store.dart';
import 'core/notification_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await AppStorage.open();
  final notifications = NotificationService();
  await notifications.init();

  // 手机端注册后台定时检查，退出 App 后也能收到主动消息通知
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await BackgroundSync.start();
    } catch (_) {
      // 后台任务注册失败不影响正常使用
    }
  }

  final state = AppState(
    storage: storage,
    mediaStore: MediaStore(),
    notifications: notifications,
  );
  await state.load();

  runApp(ChubbyFishApp(state: state));
}
