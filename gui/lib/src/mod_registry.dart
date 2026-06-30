import 'dart:convert';
import 'package:http/http.dart' as http;

/// A mod entry from mods.json, mirroring the macOS app's `Mod`.
class Mod {
  final String id;
  final String url;
  final String? urlV2; // download for the v2.x build (falls back to url)
  final String? urlMelon; // download to use when the loader is MelonLoader
  final bool v2; // available on the v2.x (Unity 2022) build
  final bool v3; // available on the v3.x+ (Unity 6) build
  final bool jalib; // depends on JALib (currently broken — hidden, banner shown)
  final String? install; // special install handler key (e.g. "quartz")

  const Mod({
    required this.id,
    required this.url,
    this.urlV2,
    this.urlMelon,
    this.v2 = true,
    this.v3 = true,
    this.jalib = false,
    this.install,
  });

  factory Mod.fromJson(Map<String, dynamic> j) => Mod(
        id: j['id'] as String,
        url: j['url'] as String,
        urlV2: j['urlV2'] as String?,
        urlMelon: j['urlMelon'] as String?,
        v2: j['v2'] as bool? ?? true,
        v3: j['v3'] as bool? ?? true,
        jalib: j['jalib'] as bool? ?? false,
        install: j['install'] as String?,
      );

  String resolvedUrl({required bool isGameV2, required bool isMelonLoader}) {
    if (isMelonLoader && urlMelon != null) return urlMelon!;
    if (isGameV2 && urlV2 != null) return urlV2!;
    return url;
  }
}

class ModRegistryException implements Exception {
  final String message;
  ModRegistryException(this.message);
  @override
  String toString() => message;
}

class ModRegistry {
  /// Source of truth at runtime — edit mods.json in the repo to change the mod
  /// list without rebuilding the app.
  static const registryUrl =
      'https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/mods.json';

  /// Fetches the mod list from the repo. Throws on any network/decode failure
  /// so the caller can surface the error rather than masking it.
  static Future<List<Mod>> fetch() async {
    final resp = await http
        .get(Uri.parse(registryUrl))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode >= 400) {
      throw ModRegistryException("Couldn't fetch the mod list (HTTP ${resp.statusCode}).");
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['mods'] as List)
        .map((e) => Mod.fromJson(e as Map<String, dynamic>))
        .toList();
    if (list.isEmpty) throw ModRegistryException('The mod list was empty.');
    return list;
  }
}
