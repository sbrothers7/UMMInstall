import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'catalog.dart';
import 'install/mod_downloader.dart';
import 'mod_store.dart';
import 'models.dart';
import 'modlist.dart';
import 'record.dart';

/// Where and for which game build a mod is installed.
class ModTarget {
  final String gameRoot;
  final bool isV2;
  final String? gameVersion;
  final bool melon;

  /// `'macos'` or `'linux'`.
  final String platform;

  const ModTarget({
    required this.gameRoot,
    required this.isV2,
    this.gameVersion,
    required this.melon,
    required this.platform,
  });
}

class ModOpsException implements Exception {
  final String message;
  ModOpsException(this.message);
  @override
  String toString() => message;
}

/// Slugs to install in order (dependencies first) and slugs nobody knows.
class InstallPlan {
  final List<CatalogEntry> order;
  final List<String> missing;
  const InstallPlan(this.order, this.missing);
}

/// One available upgrade. [from] is null when the installed version is unknown.
class Upgrade {
  final CatalogEntry entry;
  final String? from;
  final String to;

  /// Relative to the game root; replaced once the new download succeeds.
  final List<String> oldPaths;

  const Upgrade(
      {required this.entry, this.from, required this.to, required this.oldPaths});
}

class UpgradeScan {
  final List<Upgrade> upgrades;

  /// On-disk mods with no catalog match.
  final List<String> unknown;

  /// Slugs recorded or matched on disk, whether or not they need upgrading.
  final Set<String> installed;
  const UpgradeScan(this.upgrades, this.unknown, this.installed);
}

/// Install, remove and upgrade mods; the logic behind `amm modinstall`,
/// `amm mr` and `amm upgrade`. Callers save the [AmmRecord].
class ModOps {
  static InstallPlan plan(Catalog c, List<String> slugs, AmmRecord r) {
    final order = <CatalogEntry>[];
    final missing = <String>[];
    final seen = <String>{};
    final asked = {for (final s in slugs) s.toLowerCase()};

    void visit(String slug, {required bool requested}) {
      final s = slug.toLowerCase();
      if (!seen.add(s)) return;
      if (!requested && !asked.contains(s) && r.mods.containsKey(s)) return;
      final e = c.find(s);
      if (e == null) {
        missing.add(slug);
        return;
      }
      for (final d in e.dependencies) {
        visit(d, requested: false);
      }
      order.add(e);
    }

    for (final s in slugs) {
      visit(s, requested: true);
    }
    return InstallPlan(order, missing);
  }

  static Future<RecordEntry> install(CatalogEntry e, ModTarget t,
      {void Function(double)? onProgress}) async {
    final bytes = await _fetch(e, t, onProgress);
    return _place(e, t, bytes);
  }

  /// Throws if [e] can't go on [t]; otherwise downloads it.
  static Future<List<int>> _fetch(
      CatalogEntry e, ModTarget t, void Function(double)? onProgress) {
    if (e.jalib) {
      throw ModOpsException('${e.slug} depends on JALib, which is broken right now.');
    }
    if (!e.visibleOn(t.isV2)) {
      throw ModOpsException("${e.slug} isn't available for game v${t.isV2 ? 2 : 3}.");
    }
    return ModDownloader.download(_source(e, t).url, onProgress: onProgress);
  }

  static ({String url, String modsDir, bool melonNative, String? version}) _source(
      CatalogEntry e, ModTarget t) {
    final umm = p.join(t.gameRoot, 'Mods');
    final melonDir = p.join(t.gameRoot, 'UMMMods');
    final ours = e.ours;
    if (ours != null) {
      return (
        url: ours.resolvedUrl(isGameV2: t.isV2, isMelonLoader: t.melon),
        modsDir: t.melon ? melonDir : umm,
        melonNative: false,
        version: ours.resolvedVersion(isGameV2: t.isV2, isMelonLoader: t.melon),
      );
    }
    final theirs = e.theirs!;
    final l = theirs.loaders;
    String loader;
    String modsDir;
    var native = false;
    if (t.melon && l.contains('melonloader')) {
      loader = 'melonloader';
      modsDir = umm;
      native = true;
    } else if (t.melon && (l.isEmpty || l.contains('umm'))) {
      loader = 'umm';
      modsDir = melonDir;
    } else if (!t.melon && l.isNotEmpty && !l.contains('umm')) {
      throw ModOpsException(
          '${e.slug} needs MelonLoader. Switch with `amm reinstall --ml`.');
    } else {
      loader = 'umm';
      modsDir = umm;
    }
    return (
      url: ModlistClient.downloadUri(e.slug,
              loader: loader, platform: t.platform, gameVersion: t.gameVersion)
          .toString(),
      modsDir: modsDir,
      melonNative: native,
      version: theirs.version,
    );
  }

  static RecordEntry _place(CatalogEntry e, ModTarget t, List<int> bytes) {
    final s = _source(e, t);
    final placed = ModDownloader.installBytes(bytes,
        // A modlist.org name is free text; its slug is safe as a folder name.
        modId: e.ours?.id ?? e.slug,
        gameRoot: t.gameRoot,
        modsDir: s.modsDir,
        melonNative: s.melonNative);
    return RecordEntry(
      source: e.source.label,
      version: s.version,
      paths: [
        for (final path in placed)
          p.relative(path, from: t.gameRoot).replaceAll(r'\', '/'),
      ],
    );
  }

  /// Removes the mod and drops its record entry; returns the relative paths
  /// removed. [keep] archives instead of deleting.
  static List<String> remove(String slug, AmmRecord r, String gameRoot,
      {bool keep = false}) {
    final s = slug.toLowerCase();
    final key = r.mods.keys.where((k) => k.toLowerCase() == s).firstOrNull;
    final rel = <String>[];
    if (key != null) {
      rel.addAll(r.mods[key]!.paths);
    } else {
      for (final m in ModStore.scanInstalled()) {
        final base = p.basename(m.path);
        final stem = base.toLowerCase().endsWith('.dll')
            ? base.substring(0, base.length - 4)
            : base;
        final id = m.isDirectory ? ModStore.infoField(m.path, 'Id') : null;
        if (stem.toLowerCase() == s || id?.toLowerCase() == s) {
          rel.add(p.relative(m.path, from: gameRoot).replaceAll(r'\', '/'));
        }
      }
    }
    if (rel.isEmpty) throw ModOpsException('No installed mod matches "$slug".');
    final abss = [for (final path in rel) _inside(gameRoot, path)];
    for (final abs in abss) {
      if (keep) {
        ModStore.archive(InstalledMod(
            name: p.basename(abs),
            path: abs,
            isDirectory: FileSystemEntity.isDirectorySync(abs)));
      } else {
        ModStore.delete(abs);
      }
    }
    // Whatever owned a removed path is stale now, whatever its slug.
    r.mods.removeWhere((_, e) => rel.any(e.owns));
    return rel;
  }

  /// Absolute form of record path [rel]; refuses anything outside [gameRoot].
  static String _inside(String gameRoot, String rel) {
    final abs = p.normalize(p.join(gameRoot, rel));
    if (!p.isWithin(gameRoot, abs)) {
      throw ModOpsException('Refusing to touch $rel: outside the game folder.');
    }
    return abs;
  }

  static String _bare(String v) =>
      v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;

  // ponytail: "differs" not "newer"; catalog is the source of truth
  static bool _differs(String latest, String? have) =>
      have == null || _bare(latest) != _bare(have);

  /// The version an upgrade would install; null when [upgrade] would refuse.
  static String? _latest(CatalogEntry e, ModTarget t) {
    if (e.jalib || !e.visibleOn(t.isV2)) return null;
    try {
      return _source(e, t).version;
    } on ModOpsException {
      return null;
    }
  }

  static UpgradeScan upgrades(
      Catalog c, AmmRecord r, List<InstalledMod> onDisk, ModTarget t) {
    final ups = <Upgrade>[];
    final installed = {for (final k in r.mods.keys) k.toLowerCase()};
    for (final kv in r.mods.entries) {
      final have = kv.value.version;
      final e = c.find(kv.key);
      if (have == null || e == null) continue;
      final latest = _latest(e, t);
      if (latest != null && _differs(latest, have)) {
        ups.add(Upgrade(entry: e, from: have, to: latest, oldPaths: kv.value.paths));
      }
    }

    final unknown = <String>[];
    for (final m in onDisk) {
      final rel = p.relative(m.path, from: t.gameRoot).replaceAll(r'\', '/');
      if (r.ownerOf(rel) != null) continue;
      final name = p.basename(m.path);
      final id = m.isDirectory ? ModStore.infoField(m.path, 'Id')?.toLowerCase() : null;
      final e = id == null
          ? null
          : c.entries.where((e) =>
              e.slug == id ||
              e.ours?.id.toLowerCase() == id ||
              e.theirs?.name.toLowerCase() == id).firstOrNull;
      if (e == null) {
        unknown.add(name);
        continue;
      }
      installed.add(e.slug);
      final latest = _latest(e, t);
      final have = ModStore.infoField(m.path, 'Version');
      if (latest != null && _differs(latest, have)) {
        ups.add(Upgrade(entry: e, from: have, to: latest, oldPaths: [rel]));
      }
    }
    return UpgradeScan(ups, unknown, installed);
  }

  /// Downloads first, then swaps: the old paths move to
  /// `.amm/backup/<slug>`, the new version is placed, and the user's files are
  /// copied back (see [_restoreUserFiles]). Any failure after the download
  /// removes the new files and puts the old ones back.
  static Future<RecordEntry> upgrade(Upgrade u, ModTarget t,
      {void Function(double)? onProgress}) async {
    final olds = [for (final path in u.oldPaths) _inside(t.gameRoot, path)];
    final bytes = await _fetch(u.entry, t, onProgress);
    // A 200 that isn't a zip must not cost the user the old mod.
    try {
      if (ZipDecoder().decodeBytes(bytes).isEmpty) throw const FormatException();
    } catch (_) {
      throw ModDownloadException('The download was not a valid zip archive.');
    }
    final backup = p.join(t.gameRoot, '.amm', 'backup', u.entry.slug);
    ModStore.delete(backup);
    final saved = <(String, String)>[]; // (old path, its backup)
    var placed = const <String>[];
    try {
      for (final abs in olds) {
        if (FileSystemEntity.typeSync(abs) == FileSystemEntityType.notFound) continue;
        final dst = p.join(backup, p.relative(abs, from: t.gameRoot));
        Directory(p.dirname(dst)).createSync(recursive: true);
        ModStore.moveEntity(abs, dst);
        saved.add((abs, dst));
      }
      final e = _place(u.entry, t, bytes);
      placed = [for (final rel in e.paths) p.join(t.gameRoot, rel)];
      _restoreUserFiles(saved, t.gameRoot);
      ModStore.delete(backup);
      return e;
    } catch (_) {
      placed.forEach(ModStore.delete);
      for (final (abs, dst) in saved) {
        ModStore.moveEntity(dst, abs);
      }
      ModStore.delete(backup);
      rethrow;
    }
  }

  /// Copies back what the user had in the old version: under `UserData/`
  /// every file (user data wins); elsewhere, inside folders the new version
  /// also has, the files it didn't ship, except DLLs (new code wins).
  static void _restoreUserFiles(List<(String, String)> saved, String gameRoot) {
    for (final (abs, dst) in saved) {
      final userData = p.split(p.relative(abs, from: gameRoot)).first == 'UserData';
      final List<(File, String)> files;
      if (FileSystemEntity.isDirectorySync(dst)) {
        if (!userData && !FileSystemEntity.isDirectorySync(abs)) continue;
        files = [
          for (final f in Directory(dst).listSync(recursive: true, followLinks: false))
            if (f is File) (f, p.join(abs, p.relative(f.path, from: dst))),
        ];
      } else {
        files = [if (userData) (File(dst), abs)];
      }
      for (final (f, to) in files) {
        if (!userData &&
            (p.extension(to).toLowerCase() == '.dll' ||
                FileSystemEntity.typeSync(to) != FileSystemEntityType.notFound)) {
          continue;
        }
        Directory(p.dirname(to)).createSync(recursive: true);
        f.copySync(to);
      }
    }
  }
}
