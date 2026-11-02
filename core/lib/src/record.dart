import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'models.dart';

/// One mod recorded as installed by amm.
class RecordEntry {
  /// `'mods.json'` or `'modlist.org'`.
  final String source;
  final String? version;

  /// Relative to the game root, `/`-separated.
  final List<String> paths;

  const RecordEntry({required this.source, this.version, required this.paths});

  factory RecordEntry.fromJson(Map<String, dynamic> e) => RecordEntry(
        source: e['source'] as String,
        version: e['version'] as String?,
        paths: (e['paths'] as List).cast<String>(),
      );

  Map<String, dynamic> toJson() =>
      {'source': source, 'version': version, 'paths': paths};

  /// Whether [relPath] is one of [paths] or inside one.
  bool owns(String relPath) =>
      paths.any((q) => relPath == q || relPath.startsWith('$q/'));
}

/// `<game>/.amm/installed.json`: the loader method and mods amm installed.
class AmmRecord {
  Method? method;
  final Map<String, RecordEntry> mods = {};

  static String _file(String gameRoot) =>
      p.join(gameRoot, '.amm', 'installed.json');

  /// Reads the record; a missing file gives an empty one, a corrupt file is
  /// renamed to `installed.json.bad` and an empty one is returned. Entries
  /// none of whose paths exist under [gameRoot] are dropped (the next [save]
  /// persists that).
  static AmmRecord load(String gameRoot) {
    final f = File(_file(gameRoot));
    final rec = AmmRecord();
    if (!f.existsSync()) return rec;
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final m = j['method'] as String?;
      rec.method = m == null ? null : Method.parse(m);
      (j['mods'] as Map<String, dynamic>? ?? {}).forEach((slug, v) {
        final e = RecordEntry.fromJson(v as Map<String, dynamic>);
        if (!e.paths.any((q) => _exists(gameRoot, q))) return;
        rec.mods[slug] = e;
      });
      return rec;
    } catch (_) {
      try {
        f.renameSync('${f.path}.bad');
      } catch (_) {}
      return AmmRecord();
    }
  }

  static bool _exists(String gameRoot, String rel) {
    final abs = p.normalize(p.join(gameRoot, rel));
    return p.isWithin(gameRoot, abs) &&
        FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound;
  }

  void save(String gameRoot) {
    final f = File(_file(gameRoot));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'method': method?.name,
      'mods': {for (final e in mods.entries) e.key: e.value.toJson()},
    }));
  }

  /// Rewrites recorded `fromDir/<name>` path prefixes to `toDir/<name>`.
  void movePaths(String fromDir, String toDir, List<String> names) {
    for (final slug in mods.keys.toList()) {
      final e = mods[slug]!;
      mods[slug] = RecordEntry(
        source: e.source,
        version: e.version,
        paths: [
          for (final path in e.paths)
            names.any((n) => path == '$fromDir/$n' || path.startsWith('$fromDir/$n/'))
                ? '$toDir${path.substring(fromDir.length)}'
                : path,
        ],
      );
    }
  }

  /// The slug of the entry that owns [relPath] (equal to, or inside, one of
  /// its paths).
  String? ownerSlug(String relPath) =>
      mods.keys.where((k) => mods[k]!.owns(relPath)).firstOrNull;

  /// The entry that owns [relPath].
  RecordEntry? ownerOf(String relPath) => mods[ownerSlug(relPath)];
}
