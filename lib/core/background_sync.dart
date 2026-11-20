import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/bot_config.dart';

/// 后台定时检查大肥鱼主动消息的入口。
const String inboxCheckTask = 'chubbyfish_inbox_check';

/// 后台任务唯一名（注册时用）
const String _uniqueTaskName = 'chubbyfish-inbox-check';

/// App 被关闭/切后台后，由 Android WorkManager 唤醒执行。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != inboxCheckTask && task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    try {
      await _checkInboxAndNotify();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundSync {
  /// 注册 15 分钟一次的后台轮询（Android 最短间隔）。
  static Future<void> start() async {
    await Workmanager().initialize(backgroundCallbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      inboxCheckTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

Future<void> _checkInboxAndNotify() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('bot_connections');
  if (raw == null || raw.isEmpty) return;
  final connections = jsonDecode(raw);
  if (connections is! List || connections.isEmpty) return;
  final index = prefs.getInt('bot_active_index') ?? 0;
  if (index < 0 || index >= connections.length) return;
  final config = connections[index];
  if (config is! Map) return;

  final botConfig = BotConfig.fromJson(Map<String, dynamic>.from(config));
  // 局域网地址优先，其次 Tailscale 等备用地址
  final candidates = botConfig.allBaseUrls;
  if (candidates.isEmpty) return;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    List<Map>? items;
    for (final candidate in candidates) {
      final parsed = Uri.tryParse(
        candidate.contains('://') ? candidate : 'http://$candidate',
      );
      if (parsed == null || parsed.host.isEmpty) continue;

      // 自主行为插件固定监听 6188
      final uri = Uri(
        scheme: parsed.scheme.isEmpty ? 'http' : parsed.scheme,
        host: parsed.host,
        port: 6188,
        path: '/inbox',
        queryParameters: {'unread': '1'},
      );
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != 200) continue;
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        final list = json is Map ? json['messages'] : null;
        if (list is List) items = list.whereType<Map>().toList();
        if (items != null) break;
      } catch (_) {
        // 这个地址不通就试下一个
      }
    }
    if (items == null) return;

    final notifiedRaw = prefs.getString('notified_inbox_ids');
    final notified = <String>{
      if (notifiedRaw != null)
        ...((jsonDecode(notifiedRaw) as List?) ?? const [])
            .map((e) => e.toString()),
    };

    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(settings);

    for (final item in items.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      final text = item['text']?.toString().trim() ?? '';
      if (id.isEmpty || text.isEmpty || notified.contains(id)) continue;
      await plugin.show(
        id.hashCode.abs() % 2147483647,
        '大肥鱼',
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'chubbyfish_reply',
            '大肥鱼消息',
            channelDescription: '大肥鱼的新消息',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
      notified.add(id);
    }

    // 只保留最近 200 个已提醒 id，避免无限增长
    if (notified.length > 200) {
      final keep = notified.toList()..sort();
      notified.retainAll(keep.sublist(keep.length - 200));
    }
    await prefs.setString('notified_inbox_ids', jsonEncode(notified.toList()));
  } finally {
    client.close(force: true);
  }
}
