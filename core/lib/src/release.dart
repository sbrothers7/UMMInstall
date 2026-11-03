import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'net.dart';

/// The newest GitHub release: its tag and asset download URLs by file name.
class GithubRelease {
  static const repo = 'sbrothers7/UMMInstall';

  final String tag;
  final Map<String, String> assets;

  const GithubRelease(this.tag, this.assets);

  /// Throws on any network or decode failure.
  static Future<GithubRelease> latest() async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final resp = await httpClient
        .get(uri, headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode >= 400) {
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return GithubRelease(j['tag_name'] as String, {
      for (final a in ((j['assets'] as List?) ?? const []).cast<Map<String, dynamic>>())
        a['name'] as String: a['browser_download_url'] as String,
    });
  }

  /// This platform's GUI download (the macOS .zip or the Linux .tar.gz), or
  /// null when the release has none for this machine.
  String? get guiAsset {
    final suffix = switch (Platform.operatingSystem) {
      'macos' => '-macos.zip',
      // Only an x64 Linux build ships.
      'linux' => Abi.current() == Abi.linuxX64 ? '-linux.tar.gz' : null,
      _ => '-windows.zip',
    };
    if (suffix == null) return null;
    return [
      for (final MapEntry(:key, :value) in assets.entries)
        if (key.toLowerCase().endsWith(suffix)) value,
    ].firstOrNull;
  }
}

/// Whether version [remote] is newer than [local], comparing the numbers; a
/// leading `v` and anything after each number (`-beta`) are ignored.
bool isNewerVersion(String remote, String local) {
  List<int> parts(String s) => s
      .replaceAll(RegExp(r'^[vV\s]+'), '')
      .split('.')
      .map((e) => int.tryParse(RegExp(r'^\d+').stringMatch(e) ?? '') ?? 0)
      .toList();
  final r = parts(remote), l = parts(local);
  final n = r.length > l.length ? r.length : l.length;
  for (var i = 0; i < n; i++) {
    final a = i < r.length ? r[i] : 0;
    final b = i < l.length ? l[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}
