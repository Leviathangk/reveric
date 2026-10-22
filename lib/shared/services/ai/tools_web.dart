// 职责: AI Web 工具，负责 WebSearch 和 WebFetch 的 schema、description 及实现。
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/services/ai/tools_read.dart
//   lib/shared/logger/app_logger.dart
//   lib/third/html2md/html2md.dart
part of 'tools.dart';

const _webSearchDescription = '''搜索公共网络获取最新信息。

当你需要小说工作区之外的信息时使用，例如时事、库文档、产品页面或外部参考资料。

返回：
- results：按相关性排序的网页结果，包含 title、url、snippet，以及可能有的 published_time。

提示：
- 尽量使用包含产品名、版本号或日期的精准查询。
- 找到有希望的结果后，对其 `url` 调用 WebFetch 以详细阅读页面内容。

示例：
- {"query": "Riverpod AsyncNotifier docs", "limit": 5}''';

final _webSearchInputSchema = const {
  'type': 'object',
  'properties': {
    'query': {'type': 'string', 'description': '自然语言网页搜索查询。'},
    'limit': {
      'type': 'integer',
      'minimum': 1,
      'maximum': 10,
      'description': '最大返回的网页结果数。默认 5，最多 10。',
    },
  },
  'required': ['query'],
  'additionalProperties': false,
};

const _webFetchDescription = '''获取公开网页并返回适合 LLM 阅读的内容。

当你已有 URL 并需要页面内容时使用。适用于公开的 `http://` 或 `https://` 页面。

返回：
- title：页面标题（如有）。
- content：网页内容，HTML 页面会转换为 Markdown。
- format：固定为 "markdown"。
- truncated：内容是否因字符限制而被截断。

提示：
- 如果还未确定正确的 URL，先使用 WebSearch。
- 只获取最相关的页面以保持工具输出简洁。

示例：
- {"url": "https://riverpod.dev/"}''';

final _webFetchInputSchema = const {
  'type': 'object',
  'properties': {
    'url': {'type': 'string', 'description': '要获取的公开 http:// 或 https:// URL。'},
  },
  'required': ['url'],
  'additionalProperties': false,
};

const _defaultWebSearchLimit = 5;
const _webFetchMaxChars = 10240;
const _webFetchMaxResponseBytes = 5 * 1024 * 1024;
const _webFetchTimeout = Duration(seconds: 20);
const _webRequestTimeout = Duration(seconds: 20);
const _webToolUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

typedef WebToolHttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

@visibleForTesting
WebToolHttpGet webToolHttpGet = _defaultWebToolHttpGet;

@visibleForTesting
void resetWebToolHttpGetForTesting() {
  webToolHttpGet = _defaultWebToolHttpGet;
}

final _htmlTagPattern = RegExp(r'<[^>]*>');
final _htmlWhitespacePattern = RegExp(r'\s+');
final _baiduTitlePattern = RegExp(
  r'''<h3\b[^>]*>.*?<a\b[^>]*href=(["'])(.*?)\1[^>]*>(.*?)</a>.*?</h3>''',
  caseSensitive: false,
  dotAll: true,
);
final _baiduDataToolsPattern = RegExp(
  r'''\bdata-tools=(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);
final _baiduAbstractPattern = RegExp(
  r'''<div\b(?=[^>]*\bclass=(["'])[^"']*(?:c-abstract|content-right_8Zs40)[^"']*\1)[^>]*>(.*?)</div>''',
  caseSensitive: false,
  dotAll: true,
);
final _baiduLocationReplacePattern = RegExp(
  r'''(?:window\.)?location\.(?:replace|assign)\(\s*(["'])(.*?)\1\s*\)''',
  caseSensitive: false,
  dotAll: true,
);
final _baiduLocationHrefPattern = RegExp(
  r'''(?:window\.)?location\.href\s*=\s*(["'])(.*?)\1''',
  caseSensitive: false,
  dotAll: true,
);
final _metaRefreshUrlPattern = RegExp(
  r'''<meta\b[^>]*http-equiv=(["'])refresh\1[^>]*content=(["'])[^"']*url\s*=\s*'?([^"'>]+)'?[^"']*\2''',
  caseSensitive: false,
  dotAll: true,
);

@visibleForTesting
({int value, String? error}) parseToolBoundedInt(
  Object? raw, {
  required String fieldName,
  required int defaultValue,
  required int min,
  required int max,
}) {
  if (raw == null) {
    return (value: defaultValue.clamp(min, max), error: null);
  }

  final num? parsed;
  if (raw is num) {
    parsed = raw;
  } else if (raw is String) {
    parsed = num.tryParse(raw.trim());
  } else {
    parsed = null;
  }

  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return (
      value: defaultValue.clamp(min, max),
      error: '$fieldName must be a number',
    );
  }

  return (value: parsed.toInt().clamp(min, max), error: null);
}

String _htmlDecode(String input) {
  var output = input;
  const namedEntities = {
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
  };
  namedEntities.forEach((entity, value) {
    output = output.replaceAll(entity, value);
  });
  output = output.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final codePoint = int.tryParse(match.group(1) ?? '');
    return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
  });
  output = output.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    final codePoint = int.tryParse(match.group(1) ?? '', radix: 16);
    return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
  });
  return output;
}

String _normalizeWhitespace(String input) {
  return input.replaceAll(_htmlWhitespacePattern, ' ').trim();
}

void _logWebToolFailure({
  required String toolName,
  required Uri uri,
  int? statusCode,
  String? responseBody,
  Object? error,
  String? failureKind,
}) {
  final detail = [
    '[AiTools][$toolName] request failed',
    'url=$uri',
    if (statusCode != null) 'status=$statusCode',
    if (failureKind != null) 'failure_kind=$failureKind',
    if (error != null) 'error=${error.runtimeType}: $error',
    if (responseBody != null && responseBody.isNotEmpty)
      'body=${responseBody.length > 400 ? '${responseBody.substring(0, 400)}...' : responseBody}',
  ].join(' ');
  // Windows GUI 的 stderr 可能通过 Future 报写入错误，改用共享文件日志入口。
  _log.warning(detail);
}

Future<http.Response> _defaultWebToolHttpGet(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  return http.get(uri, headers: headers);
}

Future<http.Response> _getWebResponse(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  return webToolHttpGet(
    uri,
    headers: {'User-Agent': _webToolUserAgent, ...?headers},
  ).timeout(_webRequestTimeout);
}

String _stripHtmlTags(String html) {
  var text = html;
  text = text.replaceAll(
    RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
    '',
  );
  text = text.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
  text = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  text = text.replaceAll(_htmlTagPattern, ' ');
  text = _htmlDecode(text);
  text = text.replaceAll(_htmlWhitespacePattern, ' ').trim();
  return text;
}

String _firstMatchGroup(RegExp pattern, String input, int group) {
  return pattern.firstMatch(input)?.group(group) ?? '';
}

String _extractHtmlTitle(String html) {
  return _normalizeWhitespace(
    _stripHtmlTags(
      _firstMatchGroup(
        RegExp(
          r'<title\b[^>]*>(.*?)</title>',
          caseSensitive: false,
          dotAll: true,
        ),
        html,
        1,
      ),
    ),
  );
}

String _webFetchAcceptHeader() {
  return [
    'text/markdown;q=1.0',
    'text/x-markdown;q=0.9',
    'text/plain;q=0.8',
    'text/html;q=0.7',
    '*/*;q=0.1',
  ].join(', ');
}

bool _isHtmlContentType(String contentType) {
  final mime = contentType.split(';').first.trim().toLowerCase();
  return mime == 'text/html' || mime == 'application/xhtml+xml';
}

String _decodeWebResponse(http.Response response) {
  final contentType = response.headers['content-type'] ?? '';
  if (RegExp(r'charset\s*=', caseSensitive: false).hasMatch(contentType)) {
    return response.body;
  }
  // 无 charset 时优先识别 UTF-8，避免 HTTP 的 Latin-1 默认值破坏中文。
  try {
    return utf8.decode(response.bodyBytes);
  } on FormatException {
    return response.body;
  }
}

bool _isWebHtml(String body, String contentType) {
  if (_isHtmlContentType(contentType)) {
    return true;
  }
  final mime = contentType.split(';').first.trim().toLowerCase();
  if (mime.isNotEmpty &&
      mime != 'text/plain' &&
      mime != 'application/octet-stream') {
    return false;
  }
  return RegExp(
    r'^\s*(?:<!--.*?-->\s*)*(?:<!doctype\s+html\b|<html\b|<head\b|<body\b)',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(body);
}

bool _isWebChallenge(String body) {
  final title = _extractHtmlTitle(body).toLowerCase();
  final lower = body.toLowerCase();
  if (title == '百度安全验证') {
    return true;
  }
  if (title == 'duckduckgo' &&
      lower.contains('unfortunately, bots use duckduckgo too.') &&
      lower.contains('confirm this search was made by a human')) {
    return true;
  }
  // 豆瓣的 JS 工作量验证页；不能只凭正文出现 captcha/challenge 就判拦截。
  return title == '豆瓣' &&
      RegExp(
        r'''<form\b[^>]*\bid=["']sec["']''',
        caseSensitive: false,
      ).hasMatch(body) &&
      RegExp(
        r'''<input\b[^>]*\bid=["']cha["']''',
        caseSensitive: false,
      ).hasMatch(body) &&
      RegExp(
        r'''<input\b[^>]*\bid=["']sol["']''',
        caseSensitive: false,
      ).hasMatch(body) &&
      lower.contains('sha512');
}

Map<String, dynamic> _webPageFailure({
  required String toolName,
  required Uri uri,
  required http.Response response,
  required String body,
  required String kind,
  String stage = 'parse',
}) {
  _logWebToolFailure(
    toolName: toolName,
    uri: uri,
    statusCode: response.statusCode,
    responseBody: body,
    failureKind: kind,
  );
  return {
    'ok': false,
    'error_code': ToolErrorCode.unavailable.name,
    'error': switch (kind) {
      'blocked' =>
        'The website returned an anti-bot verification page instead of the requested content. Use another source; avoid immediately retrying this website.',
      'empty_content' =>
        'The page returned no readable body content. It may require JavaScript or browser verification. Try another source.',
      _ =>
        'The search response could not be recognized. This does not mean no matching pages exist. Try another source or retry later.',
    },
    'status_code': response.statusCode,
    'failure_kind': kind,
    'failure_stage': stage,
  };
}

String _convertFetchedContentToMarkdown({
  required String body,
  required Uri sourceUrl,
  required String contentType,
}) {
  if (!_isWebHtml(body, contentType)) {
    return body.trim();
  }

  return html2md
      .convert(
        body,
        imageBaseUrl: sourceUrl.origin,
        styleOptions: const {
          'headingStyle': 'atx',
          'hr': '- - -',
          'bulletListMarker': '-',
          'codeBlockStyle': 'fenced',
          'emDelimiter': '*',
        },
        ignore: const ['script', 'style', 'meta', 'link'],
      )
      .trim();
}

String _decodeJavaScriptString(String input) {
  var output = input;
  output = output.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
    final codePoint = int.tryParse(match.group(1) ?? '', radix: 16);
    return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
  });
  output = output
      .replaceAll(r'\/', '/')
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\\', r'\');
  return output;
}

mixin _AiToolManagerWebMixin on _AiToolManagerBase {
  Future<Map<String, dynamic>> _handleWebSearch(
    Map<String, dynamic> input,
  ) async {
    final query = _parseStringArgument(input['query']);
    if (query.isEmpty) {
      return {
        'ok': false,
        'error': 'Query cannot be empty',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    final limitArg = parseToolBoundedInt(
      input['limit'],
      fieldName: 'limit',
      defaultValue: _defaultWebSearchLimit,
      min: 1,
      max: 10,
    );
    if (limitArg.error != null) {
      return {
        'ok': false,
        'error': limitArg.error,
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final limit = limitArg.value;
    final uri = Uri.https('www.baidu.com', '/s', {'wd': query});

    try {
      final response = await _getWebResponse(
        uri,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logWebToolFailure(
          toolName: 'WebSearch',
          uri: uri,
          statusCode: response.statusCode,
          responseBody: response.body,
        );
        return {
          'ok': false,
          'error':
              'Web search is temporarily unavailable. Please try again later.',
          'error_code': ToolErrorCode.unavailable.name,
        };
      }

      final body = _decodeWebResponse(response);
      if (_isWebChallenge(body)) {
        return _webPageFailure(
          toolName: 'WebSearch',
          uri: uri,
          response: response,
          body: body,
          kind: 'blocked',
        );
      }
      final results = _parseBaiduSearchResults(body, limit);
      // 只有搜索页明确声明无匹配结果时，空列表才表示真正的“未找到”。
      final noResults = RegExp(
        r'''<div\b[^>]*class=["'][^"']*\bnors\b[^"']*["'][^>]*>.*?抱歉[，,]\s*没有找到与''',
        caseSensitive: false,
        dotAll: true,
      ).hasMatch(body);
      if (results.isEmpty && !noResults) {
        return _webPageFailure(
          toolName: 'WebSearch',
          uri: uri,
          response: response,
          body: body,
          kind: 'invalid_response',
        );
      }

      return {'query': query, 'engine': 'baidu', 'results': results};
    } on Exception catch (error) {
      _logWebToolFailure(toolName: 'WebSearch', uri: uri, error: error);
      return {
        'ok': false,
        'error': 'Web search failed. Please try again later.',
        'error_code': ToolErrorCode.unavailable.name,
      };
    }
  }

  List<Map<String, dynamic>> _parseBaiduSearchResults(String html, int limit) {
    final results = <Map<String, dynamic>>[];
    final resultStartPattern = RegExp(
      r'''<div\b(?=[^>]*\bclass=(["'])[^"']*(?:result|c-container)[^"']*\1)[^>]*>''',
      caseSensitive: false,
    );
    final starts = resultStartPattern
        .allMatches(html)
        .map((match) => match.start)
        .toList(growable: false);

    for (var i = 0; i < starts.length; i += 1) {
      if (results.length >= limit) {
        break;
      }

      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1] : html.length;
      final block = html.substring(start, end);
      if (_isBaiduAdBlock(block)) {
        continue;
      }

      final dataTools = _parseBaiduDataTools(block);
      final title = _normalizeWhitespace(
        _stripHtmlTags(
          dataTools['title'] ?? _firstMatchGroup(_baiduTitlePattern, block, 3),
        ),
      );
      final url = _normalizeWhitespace(
        dataTools['url'] ?? _firstMatchGroup(_baiduTitlePattern, block, 2),
      );
      final snippet = _parseBaiduSnippet(block, title);

      if (title.isNotEmpty && _isSearchResultUrl(url)) {
        results.add({
          'title': title,
          'url': url,
          if (snippet.isNotEmpty) 'snippet': snippet,
        });
      }
    }

    return results;
  }

  Map<String, String> _parseBaiduDataTools(String block) {
    final match = _baiduDataToolsPattern.firstMatch(block);
    if (match == null) {
      return const {};
    }

    try {
      final raw = _htmlDecode(match.group(2) ?? '');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const {};
      }
      final title = (decoded['title'] as String? ?? '').trim();
      final url = (decoded['url'] as String? ?? '').trim();
      return {
        if (title.isNotEmpty) 'title': title,
        if (url.isNotEmpty) 'url': url,
      };
    } on FormatException {
      return const {};
    }
  }

  String _parseBaiduSnippet(String block, String title) {
    final abstract = _firstMatchGroup(_baiduAbstractPattern, block, 2);
    if (abstract.isNotEmpty) {
      return _normalizeWhitespace(_stripHtmlTags(abstract));
    }

    final content = _normalizeWhitespace(_stripHtmlTags(block));
    if (title.isEmpty) {
      return content;
    }
    return content.replaceFirst(title, '').trim();
  }

  bool _isBaiduAdBlock(String block) {
    final lowered = block.toLowerCase();
    if (lowered.contains('ec_result') ||
        lowered.contains('ec-tuiguang') ||
        lowered.contains('data-tuiguang') ||
        lowered.contains('unified_ad') ||
        lowered.contains('/cpro/') ||
        lowered.contains('cmatch')) {
      return true;
    }

    return RegExp(
      r'<(?:span|i|em|b)\b[^>]*>\s*(?:广告|推广|商业推广)\s*</(?:span|i|em|b)>',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(block);
  }

  bool _isSearchResultUrl(String url) {
    final parsed = Uri.tryParse(url);
    return parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https');
  }

  bool _isBaiduRedirectUrl(Uri url) {
    final host = url.host.toLowerCase();
    if (host != 'baidu.com' && !host.endsWith('.baidu.com')) {
      return false;
    }
    return url.path == '/link' ||
        url.path == '/baidu.php' ||
        url.path.endsWith('/link');
  }

  Uri? _parseBaiduRedirectTarget(Uri sourceUrl, String html) {
    final candidates = [
      _firstMatchGroup(_baiduLocationReplacePattern, html, 2),
      _firstMatchGroup(_baiduLocationHrefPattern, html, 2),
      _firstMatchGroup(_metaRefreshUrlPattern, html, 3),
    ];

    for (final candidate in candidates) {
      final decoded = _htmlDecode(_decodeJavaScriptString(candidate.trim()));
      if (decoded.isEmpty) {
        continue;
      }
      final parsed = Uri.tryParse(decoded);
      final resolved = parsed == null
          ? null
          : (parsed.hasScheme ? parsed : sourceUrl.resolveUri(parsed));
      if (resolved != null &&
          resolved.hasScheme &&
          (resolved.scheme == 'http' || resolved.scheme == 'https')) {
        return resolved;
      }
    }
    return null;
  }

  Future<({Uri? url, Map<String, dynamic>? error})> _resolveBaiduRedirectUrl(
    Uri url,
  ) async {
    if (!_isBaiduRedirectUrl(url)) {
      return (url: url, error: null);
    }

    final response = await _getWebResponse(
      url,
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _logWebToolFailure(
        toolName: 'WebFetch',
        uri: url,
        statusCode: response.statusCode,
        responseBody: response.body,
      );
      return (
        url: null,
        error: {
          'ok': false,
          'error':
              'Baidu redirect URL is unavailable. HTTP ${response.statusCode}.',
          'error_code': ToolErrorCode.unavailable.name,
          'url': url.toString(),
          'status_code': response.statusCode,
        },
      );
    }

    final body = _decodeWebResponse(response);
    if (_isWebChallenge(body)) {
      return (
        url: null,
        error: _webPageFailure(
          toolName: 'WebFetch',
          uri: url,
          response: response,
          body: body,
          kind: 'blocked',
          stage: 'redirect',
        ),
      );
    }
    final finalUrl = response.request?.url;
    if (finalUrl != null &&
        finalUrl != url &&
        !_isBaiduRedirectUrl(finalUrl) &&
        _isSearchResultUrl(finalUrl.toString())) {
      return (url: finalUrl, error: null);
    }

    final resolvedUrl = _parseBaiduRedirectTarget(url, body);
    if (resolvedUrl == null) {
      _logWebToolFailure(
        toolName: 'WebFetch',
        uri: url,
        statusCode: response.statusCode,
        responseBody: body,
        failureKind: 'redirect_resolution',
      );
      return (
        url: null,
        error: {
          'ok': false,
          'error': 'Unable to resolve Baidu redirect URL.',
          'error_code': ToolErrorCode.unavailable.name,
          'url': url.toString(),
        },
      );
    }
    return (url: resolvedUrl, error: null);
  }

  Future<Map<String, dynamic>> _handleWebFetch(
    Map<String, dynamic> input,
  ) async {
    final rawUrl = _parseStringArgument(input['url']);
    if (rawUrl.isEmpty) {
      return {
        'ok': false,
        'error': 'URL cannot be empty',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    final url = Uri.tryParse(rawUrl);
    if (url == null ||
        !url.hasScheme ||
        (url.scheme != 'http' && url.scheme != 'https')) {
      return {
        'ok': false,
        'error': 'URL must start with http:// or https://',
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }

    var failureStage = _isBaiduRedirectUrl(url) ? 'redirect' : 'fetch';
    try {
      final redirectResolution = await _resolveBaiduRedirectUrl(url);
      if (redirectResolution.error != null) {
        return {
          ...redirectResolution.error!,
          'failure_stage': 'redirect',
          'failure_kind':
              redirectResolution.error!['failure_kind'] ??
              (redirectResolution.error!['status_code'] != null
                  ? 'http'
                  : 'redirect_resolution'),
        };
      }
      final fetchUrl = redirectResolution.url!;
      failureStage = 'fetch';

      final response = await _getWebResponse(
        fetchUrl,
        headers: {
          'Accept': _webFetchAcceptHeader(),
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(_webFetchTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logWebToolFailure(
          toolName: 'WebFetch',
          uri: fetchUrl,
          statusCode: response.statusCode,
          responseBody: response.body,
        );
        return {
          'ok': false,
          'error':
              'Web fetch is temporarily unavailable. Please try again later.',
          'error_code': ToolErrorCode.unavailable.name,
          'status_code': response.statusCode,
          'failure_kind': 'http',
          'failure_stage': failureStage,
        };
      }

      final contentLength = int.tryParse(
        response.headers['content-length'] ?? '',
      );
      if (contentLength != null && contentLength > _webFetchMaxResponseBytes) {
        return {
          'ok': false,
          'error': 'Fetched page is too large to read.',
          'error_code': ToolErrorCode.resource_exhausted.name,
        };
      }
      if (response.bodyBytes.length > _webFetchMaxResponseBytes) {
        return {
          'ok': false,
          'error': 'Fetched page is too large to read.',
          'error_code': ToolErrorCode.resource_exhausted.name,
        };
      }

      failureStage = 'parse';
      final contentType = response.headers['content-type'] ?? '';
      final fetchedUrl = response.request?.url ?? fetchUrl;
      final rawContent = _decodeWebResponse(response);
      final isHtml = _isWebHtml(rawContent, contentType);
      final title = isHtml ? _extractHtmlTitle(rawContent) : '';
      if (isHtml && _isWebChallenge(rawContent)) {
        return _webPageFailure(
          toolName: 'WebFetch',
          uri: fetchedUrl,
          response: response,
          body: rawContent,
          kind: 'blocked',
        );
      }
      final content = _convertFetchedContentToMarkdown(
        body: rawContent,
        sourceUrl: fetchedUrl,
        contentType: contentType,
      );
      final bodyText = isHtml
          ? _stripHtmlTags(
              rawContent.replaceAll(
                RegExp(
                  r'<(head|title|noscript)\b[^>]*>.*?</\1\s*>',
                  caseSensitive: false,
                  dotAll: true,
                ),
                '',
              ),
            )
          : content;
      if (content.isEmpty ||
          bodyText.isEmpty ||
          (isHtml && bodyText == title)) {
        return _webPageFailure(
          toolName: 'WebFetch',
          uri: fetchedUrl,
          response: response,
          body: rawContent,
          kind: 'empty_content',
        );
      }
      final totalChars = content.length;
      final truncated = totalChars > _webFetchMaxChars;
      final visibleContent = truncated
          ? content.substring(0, _webFetchMaxChars)
          : content;
      final truncationWarning = truncated
          ? 'Content was truncated to $_webFetchMaxChars characters. Fetch a more specific URL if more detail is needed.'
          : '';

      return {
        'url': fetchedUrl.toString(),
        if (fetchUrl.toString() != rawUrl) 'resolved_url': fetchUrl.toString(),
        if (title.isNotEmpty) 'title': title,
        'content': visibleContent,
        'format': 'markdown',
        'truncated': truncated,
        'returned_chars': visibleContent.length,
        'total_chars': totalChars,
        if (contentType.isNotEmpty) 'content_type': contentType,
        if (truncationWarning.isNotEmpty) 'warning': truncationWarning,
      };
    } on Exception catch (error) {
      _logWebToolFailure(toolName: 'WebFetch', uri: url, error: error);
      return {
        'ok': false,
        'error': 'Web fetch failed. Please try again later.',
        'error_code': ToolErrorCode.unavailable.name,
        'failure_stage': failureStage,
        'failure_type': safeErrorTypeName(error),
        'failure_kind': switch (error) {
          TimeoutException() => 'timeout',
          TlsException() => 'tls',
          SocketException() || http.ClientException() => 'network',
          FormatException() => 'invalid_response',
          _ => 'exception',
        },
      };
    }
  }
}
