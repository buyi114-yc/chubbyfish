import 'dart:math';

/// 简单唯一 id（避免额外依赖，后续可换成 uuid）
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999983)}';

String _two(int v) => v.toString().padLeft(2, '0');

/// 聊天时间标签：今天 -> HH:mm，昨天 -> 昨天 HH:mm，其它 -> MM-DD HH:mm
String timeLabel(int milliseconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  final hm = '${_two(t.hour)}:${_two(t.minute)}';
  if (diff == 0) return hm;
  if (diff == 1) return '昨天 $hm';
  return '${_two(t.month)}-${_two(t.day)} $hm';
}

/// 列表页时间标签：刚刚 / x 分钟前 / x 小时前 / MM-DD
String relativeTimeLabel(int milliseconds) {
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(milliseconds),
  );
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  final t = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${_two(t.month)}-${_two(t.day)}';
}

String shortText(String text, [int max = 60]) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
