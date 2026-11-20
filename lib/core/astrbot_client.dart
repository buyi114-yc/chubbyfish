import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart' show LlmException;
import 'media_store.dart';

/// AstrBot 一轮回复里可能产出的片段：文本增量 或 一张已下载到本地的图片。
sealed class AstrBotChunk {
  const AstrBotChunk();
}

class AstrBotText extends AstrBotChunk {
  AstrBotText(this.text);
  final String text;
}

class AstrBotImage extends AstrBotChunk {
  AstrBotImage(this.localPath);
  final String localPath;
}

/// 一条独立消息的结束标记：大肥鱼在一次回复里发来多条消息时，
/// 用它把内容拆成多个聊天气泡。
class AstrBotSegmentBreak extends AstrBotChunk {
  const AstrBotSegmentBreak();
}

/// AstrBot 官方 OpenAPI（v4.18.0 起）：POST {面板地址}/api/v1/chat
///
/// - 鉴权：`Authorization: Bearer abk_xxx`（或 `X-API-Key`），Key 在
///   AstrBot WebUI 的「设置 → OpenAPI」里创建，需要 chat 权限；
///   要让大肥鱼回图还需要 file 权限。
/// - 请求体：`{username, message, session_id, enable_streaming}`。
/// - 响应：SSE，每帧 `data: {JSON}`，事件对象里 `type` 为
///   plain / image / record / file / actionrow / complete / end，
///   收到 `type: "end"` 表示这一轮结束。
class AstrBotClient {
  AstrBotClient({http.Client? client, required MediaStore mediaStore})
      : _client = client ?? http.Client(),
        _mediaStore = mediaStore;

  final http.Client _client;
  final MediaStore _mediaStore;

  Uri _endpoint(String baseUrl) {
    var base = baseUrl.trim();
    if (base.isEmpty) base = 'http://127.0.0.1:6185';
    // 用户经常只填 IP:端口，缺少协议
    if (!base.contains('://')) base = 'http://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/api/v1/chat')) return Uri.parse(base);
    if (base.endsWith('/api/v1')) return Uri.parse('$base/chat');
    if (base.endsWith('/api')) return Uri.parse('$base/v1/chat');
    // 有人会把旧的 /v1 一起粘进来
    if (base.endsWith('/v1')) base = base.substring(0, base.length - 3);
    return Uri.parse('$base/api/v1/chat');
  }

  /// 把面板地址拼成接口根地址，例如 http://ip:6185
  Uri _baseUri(String baseUrl) {
    var base = baseUrl.trim();
    if (base.isEmpty) base = 'http://127.0.0.1:6185';
    if (!base.contains('://')) base = 'http://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/api/v1')) {
      base = base.substring(0, base.length - '/api/v1'.length);
    } else if (base.endsWith('/api')) {
      base = base.substring(0, base.length - '/api'.length);
    } else if (base.endsWith('/v1')) {
      base = base.substring(0, base.length - 3);
    }
    return Uri.parse(base);
  }

  /// 把面板地址拼成下载文件的地址：{base}/api/v1/files/content?filename=xxx
  Uri _fileEndpoint(String baseUrl, String filename) {
    return _baseUri(baseUrl)
        .resolve('/api/v1/files/content')
        .replace(queryParameters: {'filename': filename});
  }

  /// 上传本地图片到 AstrBot，返回附件 id，供对话时以图片消息发送。
  Future<String?> uploadImage(
    String baseUrl,
    String apiKey,
    String filePath,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _baseUri(baseUrl).resolve('/api/v1/files'),
      )..headers.addAll(_headers(apiKey));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final response =
          await _client.send(request).timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final data = json['data'];
      if (data is! Map) return null;
      final id = data['attachment_id'];
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 探测面板地址是否可达，用于多地址自动切换。
  ///
  /// 只要能拿到任意 HTTP 响应就算通：401/403 说明服务在、只是 Key 有问题，
  /// 这种情况没必要再去试备用地址。超时或连不上才返回 false。
  Future<bool> ping(
    String baseUrl,
    String apiKey, {
    // 移动数据下 Tailscale 首次建链可能要等几秒，4 秒容易误判成不通
    Duration timeout = const Duration(seconds: 7),
  }) async {
    try {
      final uri = _baseUri(baseUrl).resolve('/api/v1/plugins');
      final response =
          await _client.get(uri, headers: _headers(apiKey)).timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 600;
    } catch (_) {
      return false;
    }
  }

  /// 让插件清掉这台设备在 AstrBot 里的对话上下文。
  ///
  /// 工具调用历史一旦错乱（assistant 的 tool_calls 后面缺了对应的 tool 消息），
  /// 之后每次请求都会被模型服务端拒绝，只能清掉旧上下文重新开始。
  Future<bool> resetConversation(
    String baseUrl,
    String apiKey,
    String username,
    String sessionId,
  ) async {
    try {
      final parsed = Uri.tryParse(
        baseUrl.contains('://') ? baseUrl : 'http://$baseUrl',
      );
      if (parsed == null || parsed.host.isEmpty) return false;
      final uri = Uri(
        scheme: parsed.scheme.isEmpty ? 'http' : parsed.scheme,
        host: parsed.host,
        port: 6188,
        path: '/reset',
        queryParameters: {'username': username, 'session_id': sessionId},
      );
      final response = await _client
          .post(uri, headers: _headers(apiKey))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body is Map && body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers(String apiKey) {
    final key = apiKey.trim();
    return {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (key.isNotEmpty) ...{
        'Authorization': 'Bearer $key',
        'X-API-Key': key,
      },
    };
  }

  /// 插件自主行为服务的地址：与面板同一台机器，固定监听 6188 端口。
  ///
  /// 该服务由 AstrBot 插件 `astrbot_plugin_chubbyfish_autonomy` 提供，
  /// 负责生成动态 / 主动消息 / 签名，客户端只负责拉取展示。
  Uri? pluginUri(String baseUrl, String path, [Map<String, String>? query]) {
    var base = baseUrl.trim();
    if (base.isEmpty) return null;
    if (!base.contains('://')) base = 'http://$base';
    final parsed = Uri.tryParse(base);
    if (parsed == null || parsed.host.isEmpty) return null;
    return Uri(
      scheme: parsed.scheme.isEmpty ? 'http' : parsed.scheme,
      host: parsed.host,
      port: 6188,
      path: path,
      queryParameters: query,
    );
  }

  /// 拉取大肥鱼的签名与动态。
  Future<Map<String, dynamic>?> fetchFeed(String baseUrl) async {
    final uri = pluginUri(baseUrl, '/feed');
    if (uri == null) return null;
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return json is Map ? Map<String, dynamic>.from(json) : null;
    } catch (_) {
      return null;
    }
  }

  /// 拉取大肥鱼主动发的消息（默认只取未读）。
  Future<List<Map<String, dynamic>>> fetchInbox(
    String baseUrl, {
    bool unreadOnly = true,
  }) async {
    final uri = pluginUri(
      baseUrl,
      '/inbox',
      {'unread': unreadOnly ? '1' : '0'},
    );
    if (uri == null) return const [];
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) return const [];
      final items = json['messages'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 把录好的语音上传给插件，返回转写文字；失败时返回 null。
  ///
  /// 转写发生在 AstrBot 一侧（优先用配置里的 STT，没配就用 MiMo 语音识别），
  /// 这样手机和电脑都能用同一套识别，不依赖系统自带的听写能力。
  Future<String?> transcribeVoice(
    String baseUrl,
    String apiKey,
    String filePath,
  ) async {
    final uri = pluginUri(baseUrl, '/voice');
    if (uri == null) return null;
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers(apiKey));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final response =
          await _client.send(request).timeout(const Duration(seconds: 50));
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) return null;
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final text = (json['text'] ?? '').toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// 把用户在 App 里发的动态同步给插件。
  /// 服务端会把它单独存成「动态」，注入上下文时标明是朋友圈而不是私聊。
  Future<bool> pushMoment(
    String baseUrl,
    String apiKey,
    String text, {
    required int createdAt,
    bool hasImage = false,
  }) async {
    final uri = pluginUri(baseUrl, '/moment');
    if (uri == null) return false;
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              ..._headers(apiKey),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'text': text,
              'createdAt': createdAt,
              'hasImage': hasImage,
            }),
          )
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 上报一条图片/表情消息，让插件记住「谁发的」。
  Future<bool> pushChatLog(
    String baseUrl,
    String apiKey, {
    required String role,
    required String kind,
  }) async {
    final uri = pluginUri(baseUrl, '/chatlog');
    if (uri == null) return false;
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              ..._headers(apiKey),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'role': role, 'kind': kind}),
          )
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 标记主动消息为已读，避免下次重复弹出。
  Future<void> ackInbox(String baseUrl, List<String> ids) async {
    if (ids.isEmpty) return;
    final uri = pluginUri(baseUrl, '/ack');
    if (uri == null) return;
    try {
      await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ids': ids}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // 标记失败不影响展示
    }
  }

  /// 流式对话：每收到一段新增文本或一张图片就 yield 一次。
  ///
  /// [parts] 为 AstrBot 消息分段（可包含图片附件），传了就优先使用，
  /// 这样图片能真正出现在大肥鱼的上下文里，而不是只发一句文字描述。
  Stream<AstrBotChunk> streamChat({
    required String baseUrl,
    required String apiKey,
    required String username,
    required String sessionId,
    required String message,
    List<Map<String, dynamic>>? parts,
  }) async* {
    final request = http.Request('POST', _endpoint(baseUrl))
      ..headers.addAll(_headers(apiKey))
      ..body = jsonEncode({
        'username': username,
        'message': parts ?? message,
        'session_id': sessionId,
        'enable_streaming': true,
      });

    final response = await _client.send(request);
    final contentType = response.headers['content-type'] ?? '';

    // AstrBot 在校验失败时（如 session 归属错误）会直接返回 JSON 错误体，
    // 状态码仍是 200、content-type 为 application/json，而不是 SSE。
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        contentType.contains('application/json')) {
      final text = await response.stream.bytesToString();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw LlmException(_jsonError(text));
      }
      throw LlmException(_httpError(response.statusCode, request.url, text));
    }

    // AstrBot 可能发增量，也可能发累积全文，这里统一成增量
    var emitted = '';
    String? errorText;
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 兜底：某些错误以裸 JSON 行返回（不以 data: 开头）
      if (!trimmed.startsWith('data:')) {
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          throw LlmException(_jsonError(trimmed));
        }
        continue;
      }
      final raw = trimmed.substring(5).trim();
      if (raw.isEmpty) continue;

      Map<String, dynamic> event;
      try {
        final json = jsonDecode(raw);
        if (json is! Map) continue;
        event = Map<String, dynamic>.from(json);
      } catch (_) {
        // 跳过无法解析的帧（例如心跳/注释）
        continue;
      }

      final type = (event['type'] ?? '').toString();
      if (type == 'end') break;
      if (type == 'error') {
        throw LlmException(
          'AstrBot 返回错误：${event['message'] ?? event['code'] ?? raw}',
        );
      }

      if (type == 'image') {
        final path = await _downloadImage(baseUrl, apiKey, event['data']);
        if (path != null) yield AstrBotImage(path);
        continue;
      }
      if (type == 'record' || type == 'file') {
        // 语音/文件暂不处理
        continue;
      }

      // 工具调用事件只是内部调试用的原始 JSON（chain_type=tool_call），
      // 绝不能当成大肥鱼说的话显示出来
      final chainType = (event['chain_type'] ?? '').toString();
      if (chainType == 'tool_call' ||
          chainType == 'tool_call_result' ||
          chainType == 'reasoning') {
        continue;
      }

      // AstrBot 把模型报错也当成普通文本流回来（"LLM 响应错误"、
      // "All chat models failed: BadRequestError..." 等），收集起来，
      // 最后当错误抛出，而不是显示成一条正常回复
      if (type == 'err' || type == 'plain' || type == 'complete') {
        final maybeError = _extractText(event['data']);
        if (type == 'err' || _looksLikeLlmError(maybeError)) {
          errorText = errorText == null ? maybeError : '$errorText$maybeError';
          continue;
        }
      }

      // complete 事件带整轮全文；流式模式下 plain 片段已经把全文吐过一遍，
      // 这里跳过文本，但它同时也表示「这一条消息说完了」，用来分隔气泡。
      if (type == 'complete') {
        if (emitted.isNotEmpty) {
          emitted = '';
          yield const AstrBotSegmentBreak();
          continue;
        }
      }

      // 只有 plain（以及作为兜底的 complete 全文）才可能是正文
      if (type != 'plain' && type != 'complete') continue;

      final chunk = _extractText(event['data']);
      if (chunk.isEmpty) continue;
      // 非流式消息（每次 send 一整条）：收到下一条时不带前文，直接开新气泡
      final isStreaming = event['streaming'] == true;
      if (!isStreaming && emitted.isNotEmpty && !chunk.startsWith(emitted)) {
        emitted = '';
        yield const AstrBotSegmentBreak();
      }

      if (chunk.length > emitted.length && chunk.startsWith(emitted)) {
        yield AstrBotText(chunk.substring(emitted.length));
        emitted = chunk;
      } else {
        yield AstrBotText(chunk);
        emitted = '$emitted$chunk';
      }
    }

    if (errorText != null && errorText.trim().isNotEmpty) {
      throw LlmException(errorText.trim());
    }
  }

  /// 下载 AstrBot 回复里的图片到本地，返回本地路径；失败返回 null。
  Future<String?> _downloadImage(
    String baseUrl,
    String apiKey,
    dynamic data,
  ) async {
    final filename = data is String ? data : '';
    if (filename.isEmpty) return null;
    // AstrBot 图片事件格式是 [IMAGE]文件名，去掉前缀
    final name = filename.replaceFirst(RegExp(r'^\[IMAGE\]'), '');
    if (name.isEmpty) return null;

    try {
      final request = http.Request('GET', _fileEndpoint(baseUrl, name))
        ..headers.addAll(_headers(apiKey));
      final response = await _client.send(request).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final bytes = await response.stream.toBytes();
      if (bytes.isEmpty) return null;
      final ext = _extensionOf(name);
      return await _mediaStore.importBytes('images', bytes, extension: ext);
    } catch (_) {
      // 下载失败不影响文字回复
      return null;
    }
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return 'png';
    final ext = filename.substring(dot + 1).toLowerCase();
    if (ext.isEmpty) return 'png';
    return ext;
  }

  /// 非流式：把整轮回复的文本收完再返回，用于「测试连接」。
  Future<String> complete({
    required String baseUrl,
    required String apiKey,
    required String username,
    required String sessionId,
    required String message,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in streamChat(
      baseUrl: baseUrl,
      apiKey: apiKey,
      username: username,
      sessionId: sessionId,
      message: message,
    ).timeout(timeout)) {
      if (chunk is AstrBotText) buffer.write(chunk.text);
    }
    return buffer.toString();
  }

  /// AstrBot 有时会把模型调用失败当成普通正文推回来。
  static bool _looksLikeLlmError(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t.startsWith('LLM 响应错误') ||
        t.contains('All chat models failed') ||
        t.contains('invalid_request_error');
  }

  String _extractText(dynamic data) {
    if (data is String) return data;
    if (data is Map) {
      for (final key in const ['text', 'content', 'message', 'reply']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return '';
    }
    if (data is List) {
      final buffer = StringBuffer();
      for (final item in data) {
        buffer.write(_extractText(item));
      }
      return buffer.toString();
    }
    return '';
  }

  String _httpError(int status, Uri url, String body) {
    final detail = _shortBody(body);
    final hint = switch (status) {
      404 => '\n提示：路径不存在。AstrBot 需要 4.18 及以上版本并启用 OpenAPI；'
          '面板地址只填 http://IP:6185，不要带 /v1、/api。',
      401 || 403 => '\n提示：OpenAPI Key 无效或权限不足。'
          '请在 AstrBot WebUI「设置 → OpenAPI」重新创建 abk_ 开头的 Key，'
          '并确认有 chat 权限（管理员账号还需要 chat:admin）；'
          '要让大肥鱼回图还需要勾选 file 权限。',
      400 => '\n提示：请求参数被拒绝，确认用户名和消息内容不为空。',
      429 => '\n提示：请求过于频繁，稍后再试。',
      >= 500 => '\n提示：AstrBot 服务端异常，先看面板日志。',
      _ => '',
    };
    return '接口返回 $status：$detail\n请求地址：$url$hint';
  }

  String _shortBody(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 180 ? t : '${t.substring(0, 180)}…';
  }

  /// AstrBot 返回 JSON 错误体时提取可读消息。
  String _jsonError(String body) {
    final hint = <String>[];
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final message = json['message'] ?? json['error'] ?? json['detail'];
        if (message is String && message.isNotEmpty) hint.add(message);
        final status = json['status'];
        if (status is String && status == 'error' && hint.isEmpty) {
          hint.add('请求被拒绝');
        }
      }
    } catch (_) {
      // 不是合法 JSON，直接用原文
    }
    final text = hint.isNotEmpty ? hint.join('；') : _shortBody(body);
    if (text.contains('session_id') && text.contains('another')) {
      return '这个会话属于另一个用户名。换过昵称/QQ号后会出现，'
          '在「设置 → 接入」点一次「清空聊天记录」即可开启新会话。\n原始信息：$text';
    }
    return text;
  }
}
