import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_theme.dart';
import '../../state/app_state.dart';

/// 接入方式，首次引导和设置页共用同一套说明。
enum ConnectionKind { astrbot, phone, deepseek, custom }

class ConnectionKindInfo {
  const ConnectionKindInfo({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.steps,
    required this.fields,
    required this.tip,
    this.presetBaseUrl,
    this.presetModel,
  });

  final ConnectionKind kind;
  final String title;
  final String subtitle;
  final IconData icon;

  /// 接入步骤，从准备到能聊天按顺序排。
  final List<String> steps;

  /// 每一步需要填进 App 的内容。
  final List<String> fields;
  final String tip;
  final String? presetBaseUrl;
  final String? presetModel;

  static ConnectionKindInfo of(ConnectionKind kind) => switch (kind) {
        ConnectionKind.astrbot => _astrbot,
        ConnectionKind.phone => _phone,
        ConnectionKind.deepseek => _deepseek,
        ConnectionKind.custom => _custom,
      };

  static const _astrbot = ConnectionKindInfo(
    kind: ConnectionKind.astrbot,
    title: '接自己的 AstrBot',
    subtitle: '复用已经养好的机器人、人格和记忆',
    icon: Icons.hub_rounded,
    steps: [
      '电脑上装好 AstrBot（4.18 以上），打开 WebUI。',
      '在 WebUI 的「设置 → OpenAPI」里创建一个 Key，开头是 abk_，勾选 chat 权限。'
          'Key 只在创建时完整显示一次，先复制下来。',
      '确认面板端口。浏览器打开 http://电脑IP:6185 能看到登录页就说明通了。',
      '手机和电脑连同一个 Wi-Fi；要在外面用，就给电脑和手机都装 Tailscale，'
          '把 Tailscale 地址填进「备用地址」。',
      '回到 App：协议选「AstrBot OpenAPI」，面板地址填 http://电脑IP:6185，'
          '粘贴 abk_ Key。用户名可以留空，默认使用你的昵称。',
    ],
    fields: [
      '面板地址：http://电脑IP:6185，不要写 127.0.0.1，也不要带 /api、/v1',
      'OpenAPI Key：abk_ 开头，来自 AstrBot 面板的「设置 → OpenAPI」',
      '用户名：留空即可；填了要和 AstrBot 里认的是同一个人',
      '备用地址（可选）：Tailscale 地址，主地址不通时自动切换',
    ],
    tip: 'AstrBot 会用它自己配置的模型和人格，App 里的模型名、温度、'
        'System Prompt 不生效。6185 是面板端口，6199 是 NapCat 的 ws，'
        '跟本客户端没关系。',
    presetBaseUrl: 'http://电脑IP:6185',
    presetModel: 'default',
  );

  static const _phone = ConnectionKindInfo(
    kind: ConnectionKind.phone,
    title: '接手机上的 AstrBot（泡泡版）',
    subtitle: '机器人和 App 在同一台手机上，不用开电脑',
    icon: Icons.phone_iphone_rounded,
    steps: [
      '在手机上装好「AstrBot 泡泡版」，按它的引导完成环境安装，'
          '回到主页点「启动 AstrBot」，通知栏显示运行中再继续。',
      '在手机浏览器打开面板，一般是 http://127.0.0.1:6185；'
          '泡泡版如果换过端口，以它主页显示的为准。',
      '面板里进「设置 → OpenAPI」创建一个 Key，开头是 abk_，勾选 chat 权限；'
          '想收到大肥鱼发的图片，再把 file 权限也勾上。',
      '回到小渔窝：协议选「AstrBot OpenAPI」，面板地址填 http://127.0.0.1:6185，'
          '粘贴 abk_ Key，点「测试连接」返回连通即可。',
      '想让语音转写、主动消息、动态也能用，把 chubbyfish 的插件也装进'
          '手机里的 AstrBot（和电脑上装的是同一套）。',
    ],
    fields: [
      '面板地址：http://127.0.0.1:6185（同一台手机，所以用 127.0.0.1，不要写电脑 IP）',
      'OpenAPI Key：abk_ 开头，泡泡版面板的「设置 → OpenAPI」里创建',
      '用户名：留空即可；要和 AstrBot 里认的是同一个人',
    ],
    tip: '泡泡版的 AstrBot 面板默认就占 6185；小渔窝的网关插件检测到端口被面板占用时会'
        '自动让开，App 直接连面板，不影响使用。面板里找不到 OpenAPI 设置，说明泡泡版'
        '自带的 AstrBot 低于 4.18，升级泡泡版再来。手机和电脑别再同时跑两个 AstrBot，'
        '否则人格和记忆会各走各的。',
    presetBaseUrl: 'http://127.0.0.1:6185',
    presetModel: 'default',
  );

  static const _deepseek = ConnectionKindInfo(
    kind: ConnectionKind.deepseek,
    title: 'DeepSeek 直连',
    subtitle: '最省事，注册完填个 Key 就能聊',
    icon: Icons.bolt_rounded,
    steps: [
      '打开 platform.deepseek.com 注册并登录。',
      '进「API Keys」新建一个 Key，开头是 sk-。创建后只显示一次，先复制。',
      '回到 App：协议选「OpenAI 兼容」。',
      'Base URL 填 https://api.deepseek.com/v1，模型填 deepseek-chat。',
      '把 sk- Key 粘贴到 API Key，点「测试连接」，返回「连通」就好了。',
    ],
    fields: [
      'Base URL：https://api.deepseek.com/v1（末尾的 /v1 不能少）',
      'API Key：sk- 开头，platform.deepseek.com 的「API Keys」里创建',
      '模型名：deepseek-chat',
    ],
    tip: 'Key 只保存在本机，不会上传到任何服务器。余额和用量在 '
        'platform.deepseek.com 的「用量信息」里看，余额为 0 时会报错。',
    presetBaseUrl: 'https://api.deepseek.com/v1',
    presetModel: 'deepseek-chat',
  );

  static const _custom = ConnectionKindInfo(
    kind: ConnectionKind.custom,
    title: '其他 OpenAI 兼容服务',
    subtitle: '中转站、One-API、Ollama、LM Studio 都行',
    icon: Icons.tune_rounded,
    steps: [
      '准备一个兼容 OpenAI Chat Completions 的服务：中转站、One-API，'
          '或者本机的 Ollama、LM Studio。',
      '从服务方拿到 Base URL 和 API Key。中转站一般形如 '
          'https://域名/v1。',
      '本机模型（Ollama）的 Base URL 是 http://电脑IP:11434/v1，Key 随便填。',
      '回到 App：协议选「OpenAI 兼容」，填 Base URL、Key、模型名。',
      '点「测试连接」。报 404 多半是地址少了 /v1，报 401 多半是 Key 不对。',
    ],
    fields: [
      'Base URL：以 /v1 结尾，例如 https://api.xxx.com/v1',
      'API Key：服务方提供；本机 Ollama 可随便填',
      '模型名：服务方给的模型标识，例如 llama3、qwen2.5',
    ],
    tip: '手机访问电脑上的 Ollama 时，地址要写电脑的局域网 IP，'
        '并且电脑防火墙要放行对应端口。',
  );
}

/// 接入方式列表：首次引导和设置页都直接复用。
class ConnectionGuideList extends StatelessWidget {
  const ConnectionGuideList({
    super.key,
    required this.theme,
    this.onApply,
    this.compact = false,
  });

  final ChatTheme theme;

  /// 用户在说明里点「用这套配置」时回调，参数是选中的接入方式。
  final ValueChanged<ConnectionKind>? onApply;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final kind in ConnectionKind.values) ...[
          _row(context, ConnectionKindInfo.of(kind)),
          if (kind != ConnectionKind.values.last)
            SizedBox(height: compact ? 8 : 10),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, ConnectionKindInfo info) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context, info.kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.chromeText.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(info.icon, size: 19, color: theme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: TextStyle(
                      color: theme.chromeText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.subtitle,
                    style: TextStyle(
                      color: theme.chromeText.withValues(alpha: 0.5),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _open(context, info.kind),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('怎么接入', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, ConnectionKind kind) async {
    final applied = await showConnectionGuideSheet(
      context,
      kind,
      theme: theme,
      allowApply: onApply != null,
    );
    if (applied && onApply != null) onApply!(kind);
  }
}

/// 打开某一项接入方式的详细说明，底部可选「用这套配置」。
Future<bool> showConnectionGuideSheet(
  BuildContext context,
  ConnectionKind kind, {
  ChatTheme? theme,
  bool allowApply = false,
}) async {
  final t = theme ?? context.read<AppState>().theme;
  final info = ConnectionKindInfo.of(kind);
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.82;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.chromeText.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(info.icon, color: t.accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info.title,
                        style: TextStyle(
                          color: t.chromeText,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  info.subtitle,
                  style: TextStyle(
                    color: t.chromeText.withValues(alpha: 0.55),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '怎么接入',
                  style: TextStyle(
                    color: t.chromeText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < info.steps.length; i++) ...[
                  _numberedStep(t, i + 1, info.steps[i]),
                  if (i != info.steps.length - 1) const SizedBox(height: 9),
                ],
                const SizedBox(height: 18),
                Text(
                  '需要填什么',
                  style: TextStyle(
                    color: t.chromeText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final field in info.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: t.chromeText.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            field,
                            style: TextStyle(
                              color: t.chromeText.withValues(alpha: 0.72),
                              fontSize: 11.5,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    info.tip,
                    style: TextStyle(
                      color: t.chromeText.withValues(alpha: 0.65),
                      fontSize: 11,
                      height: 1.55,
                    ),
                  ),
                ),
                if (allowApply) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor:
                            t.isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('用这套配置'),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(
                      '关闭',
                      style: TextStyle(
                        color: t.chromeText.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}

Widget _numberedStep(ChatTheme theme, int index, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$index',
          style: TextStyle(
            color: theme.accent,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: theme.chromeText.withValues(alpha: 0.75),
            fontSize: 11.5,
            height: 1.6,
          ),
        ),
      ),
    ],
  );
}
