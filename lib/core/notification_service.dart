import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知服务。
/// - Android：使用系统自带的通知音效（默认通道音）。
/// - Windows / 其它桌面端：用 audioplayers 播放内置的柔和提示音。
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audio = AudioPlayer();
  bool _ready = false;
  bool _isDesktop = false;

  /// 动态通知固定 id：新动态覆盖旧通知，查看后按这个 id 清除。
  static const int _momentNotificationId = 7301;

  Future<void> init() async {
    _isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    try {
      if (!_isDesktop) {
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        const settings = InitializationSettings(android: android);
        await _plugin.initialize(settings);
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        // 冷启动（例如从通知点进来）时先清空上一次遗留的通知
        await _plugin.cancelAll();
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 清除通知栏里所有残留的消息。
  /// 点开 App、回到前台时调用，避免用户已经看到消息了通知还挂着。
  Future<void> cancelAll() async {
    if (!_ready || _isDesktop) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // 静默失败，不影响聊天
    }
  }

  /// 大肥鱼发动态时调用：系统通知里明确标成「动态通知」。
  /// 动态通知固定用同一个 id，后来的新动态会覆盖前一条。
  Future<void> showMoment({
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      if (_isDesktop) {
        await _audio.play(AssetSource('sounds/notify.wav'));
      } else {
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'chubbyfish_moments',
            '大肥鱼动态',
            channelDescription: '大肥鱼发新动态时的提醒',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        await _plugin.show(_momentNotificationId, title, body, details);
      }
    } catch (_) {
      // 静默失败，不影响动态同步
    }
  }

  /// 看过动态之后清掉通知栏里的动态通知。
  Future<void> cancelMoment() async {
    if (!_ready || _isDesktop) return;
    try {
      await _plugin.cancel(_momentNotificationId);
    } catch (_) {
      // 静默失败
    }
  }

  /// 大肥鱼来消息时调用。
  /// - 桌面端：每次都播放内置提示音。
  /// - 移动端：仅在后台时弹系统通知（带系统自带通知音），前台不弹避免打扰。
  Future<void> showReply({
    required String title,
    required String body,
    bool isForeground = false,
  }) async {
    if (!_ready) return;
    try {
      if (_isDesktop) {
        // 桌面端：播放内置音效
        await _audio.play(AssetSource('sounds/notify.wav'));
      } else if (!isForeground) {
        // 移动端后台：系统通知，使用通道默认音效
        const details = NotificationDetails(
          android: AndroidNotificationDetails(
            'chubbyfish_reply',
            '大肥鱼消息',
            channelDescription: '大肥鱼的新消息',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        await _plugin.show(
          DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
          title,
          body,
          details,
        );
      }
    } catch (_) {
      // 静默失败，不影响聊天
    }
  }
}
