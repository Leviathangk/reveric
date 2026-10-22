// 职责: 验证 AI Web 工具的请求、结果解析与安全失败诊断。
// 关联文件:
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/ai/tools_web.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

// 真实联网测试开关。
//
// 默认必须保持 false，避免 CI 或本地常规测试访问百度、受网络波动/验证码影响。
// 需要手动验证真实百度搜索与 WebFetch 链路时，临时改为 true 后运行：
//   fvm flutter test test/shared/services/ai/tools_web_test.dart
const _runLiveWebToolTests = false;

void main() {
  group('WebSearch', () {
    late NovelContentDatabase db;
    late AppDatabase appDb;
    late NovelContentService contentService;
    late WorkingOverlayService overlay;
    late AiToolManager toolManager;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = NovelContentService(db);
      overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
      )..registerAllTools();
    });

    tearDown(() async {
      resetWebToolHttpGetForTesting();
      await db.close();
      await appDb.close();
    });

    for (final toolName in ['WebSearch', 'WebFetch']) {
      for (final timesOut in [false, true]) {
        test('$toolName preserves failure diagnostics with unavailable stderr '
            '(timeout: $timesOut)', () async {
          final messages = <String>[];
          final originalDebugPrint = debugPrint;
          debugPrint = (message, {wrapWidth}) {
            if (message != null) {
              messages.add(message);
            }
          };
          addTearDown(() => debugPrint = originalDebugPrint);
          final unavailableStderr = _AsyncFailingStderr();
          webToolHttpGet = (uri, {headers}) async {
            if (timesOut) {
              throw TimeoutException('upstream timed out');
            }
            return http.Response('upstream unavailable', 503);
          };

          final result = await IOOverrides.runZoned(
            () => toolManager.executeTool(
              name: toolName,
              input: toolName == 'WebSearch'
                  ? {'query': 'test query'}
                  : {'url': 'https://example.invalid/page'},
            ),
            stderr: () => unavailableStderr,
          );

          expect(result['ok'], isFalse);
          expect(result['error_code'], 'unavailable');
          expect(unavailableStderr.writeCount, 0);
          final diagnostic = messages.join('\n');
          expect(diagnostic, contains('[$toolName] request failed'));
          expect(
            diagnostic,
            contains(
              toolName == 'WebSearch'
                  ? 'url=https://www.baidu.com/s?wd=test+query'
                  : 'url=https://example.invalid/page',
            ),
          );
          if (timesOut) {
            expect(diagnostic, contains('TimeoutException'));
            expect(diagnostic, contains('upstream timed out'));
          } else {
            expect(diagnostic, contains('status=503'));
            expect(diagnostic, contains('body=upstream unavailable'));
          }
        });
      }
    }

    test(
      'WebFetch exposes safe HTTP diagnostics without response content',
      () async {
        webToolHttpGet = (uri, {headers}) async =>
            http.Response('private response', 503);
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'https://example.invalid/private?token=secret'},
        );
        expect(result['status_code'], 503);
        expect(result['failure_kind'], 'http');
        expect(result['failure_stage'], 'fetch');
        expect(result.toString(), isNot(contains('private response')));
        expect(result.toString(), isNot(contains('token=secret')));
      },
    );

    test('WebFetch separates redirect timeout from fetch failure', () async {
      webToolHttpGet = (uri, {headers}) async =>
          throw TimeoutException('private uri and body');
      for (final target in {
        'https://www.baidu.com/link?url=secret': 'redirect',
        'https://example.invalid/private': 'fetch',
      }.entries) {
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': target.key},
        );
        expect(result['failure_kind'], 'timeout');
        expect(result['failure_stage'], target.value);
        expect(result.toString(), isNot(contains('private uri and body')));
      }
    });

    for (final (label, html, kind) in [
      (
        'verification',
        '<html><title>百度安全验证</title><body>请输入验证码</body></html>',
        'blocked',
      ),
      (
        'unrecognized page',
        '<html><body>Unexpected search layout</body></html>',
        'invalid_response',
      ),
    ]) {
      test(
        'WebSearch reports $label instead of successful empty results',
        () async {
          webToolHttpGet = (uri, {headers}) async => _htmlResponse(html);
          final result = await toolManager.executeTool(
            name: 'WebSearch',
            input: {'query': 'test'},
          );
          expect(result['ok'], isFalse);
          expect(result['failure_kind'], kind);
          expect(result['failure_stage'], 'parse');
          expect(result['results'], isNull);
          expect(result['error'], isNotEmpty);
        },
      );
    }

    test('WebSearch preserves an explicit no-results page', () async {
      webToolHttpGet = (uri, {headers}) async => _htmlResponse('''
        <html><title>test_百度搜索</title><body>
        <div class="nors"><p>抱歉，没有找到与“test”相关的网页。</p></div>
        </body></html>
      ''');
      final result = await toolManager.executeTool(
        name: 'WebSearch',
        input: {'query': 'test'},
      );
      expect(result['ok'], isTrue);
      expect(result['results'], isEmpty);
    });

    for (final (label, html, kind) in [
      ('empty page', '<html><body></body></html>', 'empty_content'),
      (
        'title-only shell',
        '<html><title>百度百科</title><body><div id="root"></div><script>render()</script></body></html>',
        'empty_content',
      ),
      (
        'noscript shell',
        '<html><head><title>App</title></head><body><noscript>You need to enable JavaScript to run this app.</noscript><div id="root"></div><script src="app.js"></script></body></html>',
        'empty_content',
      ),
      (
        'heading-only shell',
        '<html><title>百度百科</title><body><h1>百度百科</h1></body></html>',
        'empty_content',
      ),
      (
        'DuckDuckGo challenge',
        '<html><title>DuckDuckGo</title><body>Unfortunately, bots use DuckDuckGo too. Please complete the following challenge to confirm this search was made by a human.</body></html>',
        'blocked',
      ),
      (
        'Douban proof of work',
        '''<html><title>豆瓣</title><body>载入中
        <form id="sec"><input id="cha"><input id="sol"></form>
        <script>async function sha512() {} sub.requestSubmit();</script>
        </body></html>''',
        'blocked',
      ),
    ]) {
      test('WebFetch rejects $label even without content-type', () async {
        webToolHttpGet = (uri, {headers}) async =>
            http.Response.bytes(utf8.encode(html), 200);
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'https://example.invalid/private?token=secret'},
        );
        expect(result['ok'], isFalse);
        expect(result['failure_kind'], kind);
        expect(result['failure_stage'], 'parse');
        expect(result['content'], isNull);
        expect(result.toString(), isNot(contains('token=secret')));
      });
    }

    test(
      'WebFetch decodes UTF-8 HTML without content-type and removes scripts',
      () async {
        webToolHttpGet = (uri, {headers}) async => http.Response.bytes(
          utf8.encode(
            '<!DOCTYPE html><html><head><meta charset="utf-8"><title>作品</title></head><body><h1>作品</h1><p>正文内容</p><script>secretScript()</script></body></html>',
          ),
          200,
        );
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'https://example.invalid/page'},
        );
        expect(result['ok'], isTrue);
        expect(result['title'], '作品');
        expect(result['content'], contains('# 作品'));
        expect(result['content'], contains('正文内容'));
        expect(result['content'], isNot(contains('secretScript')));
        expect(result['format'], 'markdown');
      },
    );

    test('WebFetch accepts short text and articles about verification', () async {
      for (final response in [
        http.Response.bytes(utf8.encode('短正文'), 200),
        _htmlResponse(
          '<html><title>验证码原理</title><body><h1>验证码原理</h1><p>百度安全验证和 DuckDuckGo challenge 的介绍。</p></body></html>',
        ),
      ]) {
        webToolHttpGet = (uri, {headers}) async => response;
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'https://example.invalid/page'},
        );
        expect(result['ok'], isTrue);
        expect(result['content'], anyOf('短正文', contains('验证码原理')));
      }
    });

    test(
      'WebFetch identifies a blocked Baidu redirect without fetching again',
      () async {
        var requests = 0;
        webToolHttpGet = (uri, {headers}) async {
          requests += 1;
          return _htmlResponse(
            '<html><title>百度安全验证</title><body>验证码</body></html>',
          );
        };
        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'https://www.baidu.com/link?url=secret'},
        );
        expect(result['ok'], isFalse);
        expect(result['failure_kind'], 'blocked');
        expect(result['failure_stage'], 'redirect');
        expect(requests, 1);
      },
    );

    test('uses Baidu search with a browser user agent', () async {
      Uri? requestedUri;
      Map<String, String>? requestedHeaders;
      webToolHttpGet = (uri, {headers}) async {
        requestedUri = uri;
        requestedHeaders = headers;
        return _baiduSearchResponse();
      };

      final result = await toolManager.executeTool(
        name: 'WebSearch',
        input: {'query': 'Riverpod AsyncNotifier docs', 'limit': 1},
        callId: 'call_web_search_user_agent_test',
        emitEvents: false,
      );

      expect(result['engine'], 'baidu');
      expect(requestedUri, isNotNull);
      expect(requestedUri!.host, 'www.baidu.com');
      expect(requestedUri!.path, '/s');
      expect(
        requestedUri!.queryParameters['wd'],
        'Riverpod AsyncNotifier docs',
      );
      expect(requestedHeaders?['User-Agent'], contains('Mozilla/5.0'));
      expect(requestedHeaders?['User-Agent'], contains('Chrome/'));
      expect(requestedHeaders?['Accept-Language'], contains('zh-CN'));
    });

    test('filters Baidu ad results while keeping organic results', () async {
      webToolHttpGet = (uri, {headers}) async {
        return _baiduSearchResponse();
      };

      final result = await toolManager.executeTool(
        name: 'WebSearch',
        input: {'query': 'Reveric', 'limit': 3},
        callId: 'call_web_search_baidu_ad_filter_test',
        emitEvents: false,
      );

      final results = result['results'] as List<dynamic>;
      expect(results, hasLength(2));
      expect(results.first, {
        'title': 'Reveric 官方文档',
        'url': 'https://example.com/docs',
        'snippet': 'Reveric 文档、版本说明与使用指南。',
      });
      expect(results.last, {
        'title': 'Reveric GitHub',
        'url': 'https://github.com/looplj/reveric',
        'snippet': 'Reveric 源码仓库。',
      });
    });

    test('resolves Baidu redirect links before fetching content', () async {
      Uri? redirectRequestUri;
      Map<String, String>? redirectRequestHeaders;
      Uri? contentRequestUri;
      Map<String, String>? contentRequestHeaders;
      webToolHttpGet = (uri, {headers}) async {
        if (uri.host == 'www.baidu.com') {
          redirectRequestUri = uri;
          redirectRequestHeaders = headers;
          return _baiduRedirectResponse(uri);
        }
        contentRequestUri = uri;
        contentRequestHeaders = headers;
        return _targetHtmlResponse(uri);
      };

      final result = await toolManager.executeTool(
        name: 'WebFetch',
        input: {'url': 'http://www.baidu.com/link?url=redirected'},
        callId: 'call_web_fetch_baidu_redirect_test',
        emitEvents: false,
      );

      expect(result['error'], isNull);
      expect(redirectRequestUri?.host, 'www.baidu.com');
      expect(redirectRequestUri?.path, '/link');
      expect(redirectRequestHeaders?['User-Agent'], contains('Mozilla/5.0'));
      expect(
        contentRequestUri.toString(),
        'https://baike.baidu.com/item/Claude%20%E6%99%BA%E8%83%BD%E4%BD%93/67352013?fr=aladdin',
      );
      expect(contentRequestHeaders?['Accept'], contains('text/markdown'));
      expect(
        result['resolved_url'],
        'https://baike.baidu.com/item/Claude%20%E6%99%BA%E8%83%BD%E4%BD%93/67352013?fr=aladdin',
      );
      expect(result['url'], result['resolved_url']);
      expect(result['title'], 'Claude 智能体');
      expect(result['format'], 'markdown');
      expect(result['content'], contains('# Claude 智能体'));
      expect(result['content'], contains('这是页面正文。'));
    });

    test(
      'returns immediately when Baidu redirect link is unavailable',
      () async {
        var requestCount = 0;
        webToolHttpGet = (uri, {headers}) async {
          requestCount += 1;
          expect(uri.host, 'www.baidu.com');
          return _baiduRedirectNotFoundResponse(uri);
        };

        final result = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': 'http://www.baidu.com/link?url=missing'},
          callId: 'call_web_fetch_baidu_redirect_404_test',
          emitEvents: false,
        );

        expect(requestCount, 1);
        expect(result['error'], 'Baidu redirect URL is unavailable. HTTP 404.');
        expect(result['status_code'], 404);
        expect(result['url'], 'http://www.baidu.com/link?url=missing');
      },
    );
  });

  group(
    'Live Web tools',
    () {
      late NovelContentDatabase db;
      late AppDatabase appDb;
      late NovelContentService contentService;
      late WorkingOverlayService overlay;
      late AiToolManager toolManager;

      setUp(() {
        db = NovelContentDatabase.forTest(NativeDatabase.memory());
        appDb = AppDatabase.forTest(NativeDatabase.memory());
        contentService = NovelContentService(db);
        overlay = WorkingOverlayService(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        );
        toolManager = AiToolManager(
          contentService,
          workingOverlayService: overlay,
        )..registerAllTools();
      });

      tearDown(() async {
        resetWebToolHttpGetForTesting();
        await db.close();
        await appDb.close();
      });

      test('searches Baidu and fetches the first result as markdown', () async {
        final searchResult = await toolManager.executeTool(
          name: 'WebSearch',
          input: {'query': 'Claude 智能体', 'limit': 3},
          callId: 'call_live_web_search_test',
          emitEvents: false,
        );

        expect(searchResult['error'], isNull);
        expect(searchResult['engine'], 'baidu');
        final results = searchResult['results'] as List<dynamic>;
        expect(results, isNotEmpty);

        final firstUrl = results.first['url'] as String;
        final fetchResult = await toolManager.executeTool(
          name: 'WebFetch',
          input: {'url': firstUrl},
          callId: 'call_live_web_fetch_test',
          emitEvents: false,
        );

        expect(fetchResult['error'], isNull);
        expect(fetchResult['format'], 'markdown');
        expect((fetchResult['content'] as String).trim(), isNotEmpty);
      }, timeout: const Timeout(Duration(seconds: 45)));
    },
    skip: !_runLiveWebToolTests
        ? 'Live network test is disabled by default. Set _runLiveWebToolTests to true to run it.'
        : false,
  );
}

// 模拟无效标准错误句柄：writeln 返回后，写入错误才通过 Future 冒泡。
class _AsyncFailingStderr implements Stdout {
  var writeCount = 0;

  @override
  void writeln([Object? object = '']) {
    writeCount += 1;
    unawaited(
      Future<void>.error(
        const FileSystemException(
          'writeFrom failed',
          '',
          OSError('The handle is invalid', 6),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _htmlResponse(String html) => http.Response.bytes(
  utf8.encode(html),
  200,
  headers: {'content-type': 'text/html; charset=utf-8'},
);

http.Response _baiduSearchResponse() {
  return http.Response.bytes(
    utf8.encode(_baiduSearchHtml()),
    200,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}

String _baiduSearchHtml() {
  return '''
<html>
  <body>
    <div class="result c-container xpath-log"
      data-tools='{"title":"Reveric 官方文档","url":"https://example.com/docs"}'>
      <h3 class="t">
        <a href="https://example.com/docs">Reveric <em>官方</em>文档</a>
      </h3>
      <div class="c-abstract">Reveric 文档、版本说明与使用指南。</div>
    </div>
    <div class="result c-container ec_result"
      data-tools='{"title":"Reveric 推广","url":"https://ads.example.com/reveric"}'>
      <h3 class="t">
        <a href="https://ads.example.com/reveric">Reveric 推广</a>
      </h3>
      <span>广告</span>
      <div class="c-abstract">这是一条广告结果。</div>
    </div>
    <div class="result c-container xpath-log"
      data-tools='{"title":"Reveric GitHub","url":"https://github.com/looplj/reveric"}'>
      <h3 class="t">
        <a href="https://github.com/looplj/reveric">Reveric GitHub</a>
      </h3>
      <div class="c-abstract">Reveric 源码仓库。</div>
    </div>
  </body>
</html>
''';
}

http.Response _baiduRedirectResponse(Uri requestUri) {
  return http.Response.bytes(
    utf8.encode('''
<!DOCTYPE html><html><head><meta charset="UTF-8"><meta content="always" name="referrer"><script>try{if(window.opener&&window.opener.bds&&window.opener.bds.pdc&&window.opener.bds.pdc.sendLinkLog){window.opener.bds.pdc.sendLinkLog();}}catch(e) {};var timeout = 0;if(/bdlksmp/.test(window.location.href)){var reg = /bdlksmp=([^=&]+)/,matches = window.location.href.match(reg);timeout = matches[1] ? matches[1] : 0};setTimeout(function(){window.location.replace("https://baike.baidu.com/item/Claude%20%E6%99%BA%E8%83%BD%E4%BD%93/67352013?fr=aladdin")},timeout);window.opener=null;</script>
<noscript><META http-equiv="refresh" content="0;URL='https://baike.baidu.com/item/Claude%20%E6%99%BA%E8%83%BD%E4%BD%93/67352013?fr=aladdin'"></noscript>
'''),
    200,
    request: http.Request('GET', requestUri),
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}

http.Response _baiduRedirectNotFoundResponse(Uri requestUri) {
  return http.Response.bytes(
    utf8.encode('''
<!DOCTYPE html>
<html lang="zh-CN">
  <head><meta charset="UTF-8"><title>出错啦！</title></head>
  <body>出错啦！</body>
</html>
'''),
    404,
    request: http.Request('GET', requestUri),
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}

http.Response _targetHtmlResponse(Uri requestUri) {
  return http.Response.bytes(
    utf8.encode('''
<!DOCTYPE html>
<html>
  <head>
    <title>Claude 智能体</title>
    <script>ignored()</script>
    <style>body { color: red; }</style>
  </head>
  <body>
    <h1>Claude 智能体</h1>
    <p>这是页面正文。</p>
  </body>
</html>
'''),
    200,
    request: http.Request('GET', requestUri),
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
}
