// 职责: 全局浮窗聊天 AI 服务 — Agent 运行时 + 工具调度、WebSearch/WebFetch/SearchNovels/SearchNovelContent
// 关联文件:
//   lib/shared/providers/floating_chat_provider.dart
//   lib/shared/agent/agent.dart
//   lib/shared/services/ai/ai_chat_service.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/models/ai_provider.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import '../database/novel_content_database.dart';
import '../agent/agent.dart';
import '../agent/agent_event.dart';
import '../logger/app_logger.dart';
import '../models/ai_provider.dart';
import '../models/ai_run_failure.dart';
import '../services/ai/ai_service_config.dart';
import '../services/ai/chat.dart';
import '../services/ai/provider_initializer.dart';
import '../services/ai/tools.dart';
import '../services/novel_content.dart';

final _log = AppLogger.forModule('FloatingChat');

const _systemPrompt =
    '''You are a helpful assistant for a novel-writing application called Reveric.
You can:
- Search the web for information using WebSearch and WebFetch tools.
- Search the user's novel library using SearchNovels tool.
- Search within the content of a specific novel (chapters) using SearchNovelContent tool.

Be concise and helpful. When the user asks about their novels, first use SearchNovels to find the relevant novel, then use SearchNovelContent to search inside specific novels if needed.
When the user asks for external information, use WebSearch to find it and WebFetch to read pages in detail.''';

const _ua = 'Mozilla/5.0 (compatible; Reveric/1.0)';
const _wt = Duration(seconds: 20);
final _tagRe = RegExp(r'<[^>]*>');
final _wsRe = RegExp(r'\s+');

String _hd(String input) {
  var o = input;
  const m = {
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
  };
  m.forEach((k, v) => o = o.replaceAll(k, v));
  return o.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final c = int.tryParse(m.group(1) ?? '');
    return c == null ? m.group(0)! : String.fromCharCode(c);
  });
}

String _n(String s) => s.replaceAll(_wsRe, ' ').trim();

String _sh(String h) {
  var t = h;
  t = t.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
  t = t.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
  t = t.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  t = t.replaceAll(_tagRe, ' ');
  t = _hd(t);
  return t.replaceAll(_wsRe, ' ').trim();
}

List<Map<String, dynamic>> _parseDuckGo(String html, int limit) {
  final r = <Map<String, dynamic>>[];
  final bp = RegExp(r'<div class="result[^"]*"[^>]*>.*?</div>', dotAll: true);
  final tp = RegExp(r'<a[^>]*class="result__a"[^>]*>(.*?)</a>');
  final lp = RegExp(r'uddg=([^"&]+)');
  final sp = RegExp(
    r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
    dotAll: true,
  );
  for (final m in bp.allMatches(html)) {
    if (r.length >= limit) break;
    final b = m.group(0) ?? '';
    final t = _n(_sh(tp.firstMatch(b)?.group(1) ?? ''));
    final ru = lp.firstMatch(b)?.group(1) ?? '';
    final u = Uri.decodeComponent(_n(ru));
    final s = _n(_sh(sp.firstMatch(b)?.group(1) ?? ''));
    if (t.isNotEmpty && u.isNotEmpty) {
      r.add({'title': t, 'url': u, if (s.isNotEmpty) 'snippet': s});
    }
  }
  return r;
}

Map<String, dynamic>? _parseJina(String body) {
  final raw = jsonDecode(body);
  if (raw is! Map) return null;
  final d = raw['data'];
  return d is Map ? Map<String, dynamic>.from(d) : null;
}

void _lf(String tool, Uri uri, [int? sc, String? body, Object? err]) {
  _log.warning(
    [
      '[$tool] fail',
      'url=$uri',
      if (sc != null) 'status=$sc',
      if (err != null) 'error=${err.runtimeType}: $err',
      if (body != null && body.isNotEmpty)
        'body=${body.length > 200 ? '${body.substring(0, 200)}...' : body}',
    ].join(' '),
  );
}

typedef _Handler = Future<Map<String, dynamic>> Function(Map<String, dynamic>);

class FloatingChatService implements AgentToolDispatcher {
  FloatingChatService({
    required AiProvider config,
    required AppDatabase database,
  }) : _config = config,
       _database = database;

  final AiProvider _config;
  final AppDatabase _database;

  AiProviderInitializer? _initializer;
  AiClient? _client;
  Agent? _agent;
  final Map<String, _Handler> _handlers = {};
  final List<ToolDef> _toolDefs = [];

  bool get isInitialized => _agent != null;

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) async {
    final handler = _handlers[name];
    if (handler == null) {
      return {'ok': false, 'error': 'tool_not_found', 'name': name};
    }
    try {
      return await handler(input);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  @override
  List<String> allToolNames() => _handlers.keys.toList();

  @override
  List<ToolDef> allToolDefs() => _toolDefs;

  @override
  List<ToolDef> toolDefsForNames(List<String> names) {
    return _toolDefs.where((t) => names.contains(t.name)).toList();
  }

  List<ToolDef> get toolDefs => _toolDefs;

  Future<void> initialize() async {
    if (_agent != null) return;

    final models = _config.availableModels;
    if (models.isEmpty) {
      throw StateError('${_config.displayName} has no available chat models.');
    }
    final model = models.first;

    _initializer = AiProviderInitializer(config: _config, chatModel: model);
    await _initializer!.initialize();

    _registerTools();

    final clientConfig = AiServiceConfig(provider: _config, chatModel: model);
    _client = AiClient.fromConfig(clientConfig);
    await _client!.initialize();

    final client = _client!;
    _agent = Agent.custom(
      id: 'floating_chat',
      systemPrompt: _systemPrompt,
      client: client.providerClient,
      providerId: client.providerId,
      config: client.agentConfig,
      toolManager: this,
      allowedTools: [
        'WebSearch',
        'WebFetch',
        'SearchNovels',
        'SearchNovelContent',
      ],
    );
  }

  void _registerTools() {
    _handlers['WebSearch'] = _handleWebSearch;
    _toolDefs.add(
      ToolDef(
        name: 'WebSearch',
        description:
            'Search the public web for recent information. Inputs: query (required), limit (optional, default 5, max 10).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'limit': {'type': 'integer', 'minimum': 1, 'maximum': 10},
          },
          'required': ['query'],
        },
      ),
    );

    _handlers['WebFetch'] = _handleWebFetch;
    _toolDefs.add(
      ToolDef(
        name: 'WebFetch',
        description:
            'Fetch a public web page. Inputs: url (required), format (markdown/text/html, default markdown), max_chars (default 12000).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'format': {
              'type': 'string',
              'enum': ['markdown', 'text', 'html'],
            },
            'max_chars': {'type': 'integer', 'minimum': 500, 'maximum': 50000},
          },
          'required': ['url'],
        },
      ),
    );

    _handlers['SearchNovels'] = _handleSearchNovels;
    _toolDefs.add(
      ToolDef(
        name: 'SearchNovels',
        description:
            'Search the user\'s novel library. Find novels by title, description, or tags matching the query. Inputs: query (required).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
      ),
    );

    _handlers['SearchNovelContent'] = _handleSearchNovelContent;
    _toolDefs.add(
      ToolDef(
        name: 'SearchNovelContent',
        description:
            'Search within the content of a specific novel. Use this AFTER finding the novel with SearchNovels. Searches chapter titles and body content. Inputs: novelId (required), query (required).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'novelId': {'type': 'string'},
            'query': {'type': 'string'},
          },
          'required': ['novelId', 'query'],
        },
      ),
    );
  }

  Stream<AgentEvent> chatStream(String userMessage) async* {
    if (_agent == null) throw Exception('Not initialized');

    try {
      await for (final event in _agent!.process(userMessage)) {
        yield event;
      }
    } on StateError catch (e, stackTrace) {
      _log.error('agent error', error: e, stackTrace: stackTrace);
      yield AgentError(
        const AiRunFailure.requestFailed(),
        technicalMessage: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> _handleWebSearch(
    Map<String, dynamic> input,
  ) async {
    final query = (input['query'] as String? ?? '').trim();
    if (query.isEmpty) return {'error': 'Query cannot be empty'};
    final limit = ((input['limit'] as num?)?.toInt() ?? 5).clamp(1, 10);
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
    try {
      final res = await http
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(_wt);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lf('WebSearch', uri, res.statusCode, res.body);
        return {'error': 'Web search is temporarily unavailable.'};
      }
      return {
        'query': query,
        'engine': 'duckduckgo',
        'results': _parseDuckGo(res.body, limit),
      };
    } on Exception catch (e) {
      _lf('WebSearch', uri, null, null, e);
      return {'error': 'Web search failed.'};
    }
  }

  Future<Map<String, dynamic>> _handleWebFetch(
    Map<String, dynamic> input,
  ) async {
    final rawUrl = (input['url'] as String? ?? '').trim();
    if (rawUrl.isEmpty) return {'error': 'URL cannot be empty'};
    final url = Uri.tryParse(rawUrl);
    if (url == null ||
        !url.hasScheme ||
        (url.scheme != 'http' && url.scheme != 'https')) {
      return {'error': 'URL must start with http:// or https://'};
    }
    final format =
        (input['format'] as String?)?.trim().toLowerCase() ?? 'markdown';
    if (!['markdown', 'text', 'html'].contains(format)) {
      return {'error': 'Invalid format.'};
    }
    final maxChars = ((input['max_chars'] as num?)?.toInt() ?? 12000).clamp(
      500,
      50000,
    );
    final ju = Uri.https('r.jina.ai', '/');
    try {
      final res = await http
          .post(
            ju,
            headers: {'Accept': 'application/json', 'User-Agent': _ua},
            body: {'url': rawUrl},
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lf('WebFetch', ju, res.statusCode, res.body);
        return {'error': 'Web fetch is temporarily unavailable.'};
      }
      final data = _parseJina(res.body);
      if (data == null) return {'error': 'Unreadable response.'};
      final rc = (data['content'] as String? ?? '').trim();
      final title = (data['title'] as String? ?? '').trim();
      final fu = (data['url'] as String? ?? rawUrl).trim();
      String content;
      if (format == 'html') {
        content = rc;
      } else if (format == 'text') {
        content = _sh(rc);
      } else {
        content = rc;
      }
      final total = content.length;
      final trunc = total > maxChars;
      return {
        'url': fu,
        if (title.isNotEmpty) 'title': title,
        'content': trunc ? content.substring(0, maxChars) : content,
        'format': format == 'text'
            ? 'text'
            : (format == 'html' ? 'html' : 'markdown'),
        'truncated': trunc,
        'returned_chars': trunc ? maxChars : total,
        'total_chars': total,
      };
    } on Exception catch (e) {
      _lf('WebFetch', ju, null, null, e);
      return {'error': 'Web fetch failed.'};
    }
  }

  Future<Map<String, dynamic>> _handleSearchNovels(
    Map<String, dynamic> input,
  ) async {
    final query = (input['query'] as String? ?? '').trim().toLowerCase();
    if (query.isEmpty) return {'error': 'Query cannot be empty'};
    try {
      final novels = await _database.novelDao.watchAll().first;
      final results = novels
          .where(
            (n) =>
                n.title.toLowerCase().contains(query) ||
                n.description.toLowerCase().contains(query) ||
                n.tags.any((t) => t.toLowerCase().contains(query)),
          )
          .map(
            (n) => {
              'id': n.id,
              'title': n.title,
              'description': n.description,
              'status': n.status,
              'wordCount': n.wordCount,
              'tags': n.tags,
            },
          )
          .toList();
      return {'query': query, 'count': results.length, 'novels': results};
    } on Exception catch (e, stackTrace) {
      _log.error('SearchNovels error', error: e, stackTrace: stackTrace);
      return {'error': 'Novel search failed.'};
    }
  }

  Future<Map<String, dynamic>> _handleSearchNovelContent(
    Map<String, dynamic> input,
  ) async {
    final novelId = (input['novelId'] as String? ?? '').trim();
    final query = (input['query'] as String? ?? '').trim();
    if (novelId.isEmpty) return {'error': 'novelId is required'};
    if (query.isEmpty) return {'error': 'query is required'};
    try {
      final novel = await _database.novelDao.get(novelId);
      if (novel == null) return {'error': 'Novel not found: $novelId'};
      final dbPath = novel.contentDatabasePath;
      if (dbPath == null || dbPath.isEmpty) {
        return {'error': 'Novel has no content database yet.'};
      }
      final contentDb = NovelContentDatabase(dbPath);
      try {
        final cs = NovelContentService(contentDb);
        final chapters = await cs.getChapters();
        final lowerQuery = query.toLowerCase();
        final matches = <Map<String, dynamic>>[];
        for (final ch in chapters) {
          final chContent = ch.content;
          final titleMatch = (ch.title ?? '').toLowerCase().contains(
            lowerQuery,
          );
          final bodyLower = chContent.toLowerCase();
          final bodyMatch = bodyLower.contains(lowerQuery);
          if (titleMatch || bodyMatch) {
            final snippets = <String>[];
            if (bodyMatch) {
              final idx = bodyLower.indexOf(lowerQuery);
              if (idx >= 0) {
                final start = (idx - 40).clamp(0, chContent.length);
                final end = (idx + lowerQuery.length + 80).clamp(
                  0,
                  chContent.length,
                );
                snippets.add(
                  (start > 0 ? '...' : '') +
                      chContent.substring(start, end).replaceAll('\n', ' ') +
                      (end < chContent.length ? '...' : ''),
                );
              }
            }
            matches.add({
              'chapterId': ch.id,
              'title': ch.title,
              'snippets': snippets,
              'wordCount': ch.wordCount,
            });
          }
        }
        return {
          'novelId': novelId,
          'novelTitle': novel.title,
          'query': query,
          'matchCount': matches.length,
          'matches': matches.take(10).toList(),
        };
      } finally {
        await contentDb.close();
      }
    } on Exception catch (e, stackTrace) {
      _log.error('SearchNovelContent error', error: e, stackTrace: stackTrace);
      return {'error': 'Content search failed.'};
    }
  }

  void cancel() {
    _client?.cancel();
  }

  void dispose() {
    cancel();
    _agent = null;
    _client = null;
    _initializer = null;
    _handlers.clear();
  }
}
