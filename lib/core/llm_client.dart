import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmException implements Exception {
  LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 只依赖 OpenAI 兼容协议（/chat/completions + SSE 流式）。
/// 因此 DeepSeek 官方、AstrBot 网关、自建中转、OneAPI 等都能直接切换 baseUrl。
class LlmClient {
  LlmClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _endpoint(String baseUrl) {
    var base = baseUrl.trim();
    if (base.isEmpty) base = 'https://api.deepseek.com/v1';
    // 用户经常只填 IP:端口，缺少协议
    if (!base.contains('://')) base = 'http://$base';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) return Uri.parse(base);
    return Uri.parse('$base/chat/completions');
  }

  Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      };

  /// 流式对话：每收到一段增量文本就 yield 一次。
  Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.8,
  }) async* {
    final request = http.Request('POST', _endpoint(baseUrl))
      ..headers.addAll(_headers(apiKey))
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': true,
      });

    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.stream.bytesToString();
      throw LlmException(
        _httpError(response.statusCode, request.url, text),
      );
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') break;

      try {
        final json = jsonDecode(data);
        if (json is! Map) continue;
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        final delta = choice['delta'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) yield content;
      } catch (_) {
        // 跳过无法解析的 SSE 片段（例如心跳/注释行）
      }
    }
  }

  /// 非流式调用，用于“测试连接”。
  Future<String> complete({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.0,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = http.Request('POST', _endpoint(baseUrl))
      ..headers.addAll(_headers(apiKey))
      ..body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'stream': false,
      });

    final response = await _client.send(request).timeout(timeout);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException(_httpError(response.statusCode, request.url, body));
    }

    final json = jsonDecode(body);
    if (json is! Map) throw LlmException('返回内容不是合法 JSON');
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) throw LlmException('模型没有返回内容');
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    return content is String ? content : '';
  }

  String _httpError(int status, Uri url, String body) {
    final detail = _shortBody(body);
    final hint = switch (status) {
      404 =>
        '\n提示：路径不存在，通常是 Base URL 填错。DeepSeek 应为 '
            'https://api.deepseek.com/v1；AstrBot 自带的 6185 端口只有 WebUI，'
            '需要额外启用 OpenAI 兼容网关后才能用 /v1。',
      401 || 403 => '\n提示：API Key 无效或没有访问权限。',
      429 => '\n提示：请求过于频繁或额度已用尽。',
      >= 500 => '\n提示：服务端异常，稍后再试。',
      _ => '',
    };
    return '接口返回 $status：$detail\n请求地址：$url$hint';
  }

  String _shortBody(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 180 ? t : '${t.substring(0, 180)}…';
  }
}
