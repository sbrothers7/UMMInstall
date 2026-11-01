import 'dart:convert';
import 'net.dart';
import 'mod_registry.dart';

/// A mod listed on modlist.org.
class ModlistMod {
  final String slug;
  final String name;
  final String summary;
  final String? version; // latestVersion.version
  final List<String> dependencies; // slugs
  final Set<String> loaders; // empty means the file works with any loader

  const ModlistMod({
    required this.slug,
    required this.name,
    this.summary = '',
    this.version,
    this.dependencies = const [],
    this.loaders = const {},
  });

  factory ModlistMod.fromJson(Map<String, dynamic> j) {
    final latest = j['latestVersion'] as Map<String, dynamic>?;
    final files = (latest?['files'] as List?) ?? const [];
    return ModlistMod(
      slug: j['slug'] as String,
      name: j['name'] as String,
      summary: j['summary'] as String? ?? '',
      version: latest?['version'] as String?,
      dependencies: ((j['dependencies'] as List?) ?? const []).cast<String>(),
      loaders: {
        for (final f in files)
          if ((f as Map<String, dynamic>)['loader'] != null) f['loader'] as String
      },
    );
  }
}

class ModlistClient {
  static const base = 'https://modlist.org/api/mods';

  /// Fetches every ADOFAI mod, following pagination. Throws on any failure.
  static Future<List<ModlistMod>> fetchAll() async {
    final mods = <ModlistMod>[];
    var page = 1;
    while (true) {
      final resp = await httpClient
          .get(Uri.parse('$base?game=adofai&limit=50&page=$page'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 400) {
        throw ModRegistryException("Couldn't fetch modlist.org (HTTP ${resp.statusCode}).");
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      mods.addAll((body['mods'] as List)
          .map((e) => ModlistMod.fromJson(e as Map<String, dynamic>)));
      final total = (body['pagination'] as Map<String, dynamic>)['totalPages'] as int;
      if (page >= total) return mods;
      page++;
    }
  }

  static Uri downloadUri(String slug,
          {required String loader, required String platform, String? gameVersion}) =>
      Uri.parse('$base/$slug/download').replace(queryParameters: {
        'loader': loader,
        'platform': platform,
        'gameVersion': ?gameVersion,
      });
}
