// 职责: 解析并校验插件清单与入口路径。
// 关联文件:
//   lib/shared/services/plugins/host.dart
import 'package:pub_semver/pub_semver.dart';

class PluginManifest {
  PluginManifest._(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get version => json['version'] as String;
  String get main => json['main'] as String;
  String? get description => json['description'] as String?;
  String? get author => json['author'] as String?;
  bool get defaultEnabled => json['defaultEnabled'] as bool? ?? false;
  List<String> get platforms => List<String>.from(
    json['platforms'] as List? ?? ['windows', 'macos', 'android'],
  );
  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    for (final key in ['id', 'name', 'version', 'pluginApiVersion', 'main']) {
      if (json[key] is! String || (json[key] as String).trim().isEmpty) {
        throw FormatException('Invalid manifest $key');
      }
    }
    if (!RegExp(r'^[a-z0-9]+(\.[a-z0-9-]+)+$').hasMatch(json['id'] as String)) {
      throw const FormatException('Invalid plugin id');
    }
    Version.parse(json['version'] as String);
    final api = json['pluginApiVersion'] as String;
    final constraint = api == '^1'
        ? VersionConstraint.parse('>=1.0.0 <2.0.0')
        : VersionConstraint.parse(api);
    if (!constraint.allows(Version(1, 0, 0))) {
      throw FormatException('Unsupported plugin API: $api');
    }
    final main = json['main'] as String;
    if (main.startsWith('/') ||
        main.contains('\\') ||
        main.contains(':') ||
        main.split('/').any((s) => s == '..' || s.isEmpty)) {
      throw const FormatException('Entry must remain within plugin package');
    }
    for (final key in ['description', 'author', 'uiProtocol']) {
      if (json.containsKey(key) && json[key] is! String) {
        throw FormatException('Invalid $key');
      }
    }
    if (json.containsKey('defaultEnabled') && json['defaultEnabled'] is! bool) {
      throw const FormatException('Invalid defaultEnabled');
    }
    for (final key in ['platforms', 'permissions']) {
      if (json.containsKey(key) &&
          (json[key] is! List ||
              (json[key] as List).any((v) => v is! String))) {
        throw FormatException('Invalid $key');
      }
    }
    if ((json['platforms'] as List? ?? []).any(
      (p) => !['windows', 'macos', 'android'].contains(p),
    )) {
      throw const FormatException('Unknown platform');
    }
    if (json.containsKey('settings') &&
        json['settings'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings');
    }
    return PluginManifest._(Map.unmodifiable(json));
  }
}
