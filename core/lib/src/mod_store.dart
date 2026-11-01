import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'platform/game_paths.dart';

/// On-disk handling of installed and archived mods (Mods/, UMMMods/ and the
/// `.adofai-archive` folder).
class ModStore {
  /// Scans the game's mods folders (Mods/ and UMMMods/) for installed mods:
  /// folders (UMM-style) and loose .dll files (MelonLoader-style).
  static List<InstalledMod> scanInstalled() {
    final result = <InstalledMod>[];
    final seen = <String>{};
    for (final dirPath in {GamePaths.ummModsPath, GamePaths.melonModsPath}) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync()) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name == '__MACOSX') continue;
        if (!seen.add(entity.path)) continue;
        if (entity is Directory) {
          result.add(InstalledMod(
            name: infoField(entity.path, 'DisplayName') ?? name,
            path: entity.path,
            isDirectory: true,
          ));
        } else if (entity is File && name.toLowerCase().endsWith('.dll')) {
          result.add(InstalledMod(name: name, path: entity.path, isDirectory: false));
        }
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Mods soft-deleted into the archive, sorted by name.
  static List<ArchivedMod> scanArchived() {
    final root = Directory(GamePaths.archivePath);
    if (!root.existsSync()) return [];
    final result = <ArchivedMod>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final meta = File(p.join(entity.path, '_archive.json'));
      if (!meta.existsSync()) continue;
      try {
        final j = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
        result.add(ArchivedMod(
          name: j['name'] as String? ?? p.basename(entity.path),
          key: p.basename(entity.path),
          originPath: j['origin'] as String,
          isDirectory: j['isDirectory'] as bool? ?? true,
          payloadPath: p.join(entity.path, j['payload'] as String),
        ));
      } catch (_) {}
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Permanently removes a mod file or folder; errors are ignored.
  static void delete(String path) {
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        Directory(path).deleteSync(recursive: true);
      } else if (File(path).existsSync()) {
        File(path).deleteSync();
      }
    } catch (_) {}
  }

  /// "Keep Data": moves [mod] into the archive so it stops loading but can be
  /// restored later.
  static void archive(InstalledMod mod) {
    final base = p.basename(mod.path);
    final entryDir = p.join(GamePaths.archivePath, base);
    if (Directory(entryDir).existsSync()) {
      Directory(entryDir).deleteSync(recursive: true);
    }
    Directory(entryDir).createSync(recursive: true);
    moveEntity(mod.path, p.join(entryDir, base));
    File(p.join(entryDir, '_archive.json')).writeAsStringSync(jsonEncode({
      'name': mod.name,
      'origin': mod.path,
      'isDirectory': mod.isDirectory,
      'payload': base,
    }));
  }

  /// Puts an archived mod back at its original location.
  static void restore(ArchivedMod a) {
    Directory(p.dirname(a.originPath)).createSync(recursive: true);
    if (FileSystemEntity.typeSync(a.originPath) !=
        FileSystemEntityType.notFound) {
      if (FileSystemEntity.isDirectorySync(a.originPath)) {
        Directory(a.originPath).deleteSync(recursive: true);
      } else {
        File(a.originPath).deleteSync();
      }
    }
    if (FileSystemEntity.typeSync(a.payloadPath) !=
        FileSystemEntityType.notFound) {
      moveEntity(a.payloadPath, a.originPath);
    }
    deleteArchived(a);
  }

  /// Removes an archive entry for good.
  static void deleteArchived(ArchivedMod a) {
    final entryDir = p.join(GamePaths.archivePath, a.key);
    if (Directory(entryDir).existsSync()) {
      Directory(entryDir).deleteSync(recursive: true);
    }
  }

  /// UMM mods are folders in [dir] that contain an info.json (any case).
  static List<String> findUmmMods(String dir) {
    if (!Directory(dir).existsSync()) return [];
    final result = <String>[];
    for (final entity in Directory(dir).listSync()) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final hasInfo = entity
          .listSync()
          .any((f) => p.basename(f.path).toLowerCase() == 'info.json');
      if (hasInfo) result.add(name);
    }
    result.sort();
    return result;
  }

  /// Moves the folders [names] from [from] to [to], returning those moved.
  /// A failure is passed to [onError] and the rest still move.
  static List<String> moveMods(List<String> names, String from, String to,
      {void Function(String name, Object error)? onError}) {
    Directory(to).createSync(recursive: true);
    final moved = <String>[];
    for (final name in names) {
      try {
        moveEntity(p.join(from, name), p.join(to, name));
        moved.add(name);
      } catch (e) {
        onError?.call(name, e);
      }
    }
    return moved;
  }

  /// A string field from a mod folder's `Info.json`/`info.json`, if non-empty.
  static String? infoField(String folder, String key) {
    for (final fname in const ['Info.json', 'info.json']) {
      final f = File(p.join(folder, fname));
      if (!f.existsSync()) continue;
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final v = j[key] as String?;
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
    }
    return null;
  }

  /// Moves a file or directory to [dst] (replacing it), falling back to
  /// copy + delete across volumes.
  static void moveEntity(String src, String dst) {
    final isDir = FileSystemEntity.isDirectorySync(src);
    if (isDir && Directory(dst).existsSync()) {
      Directory(dst).deleteSync(recursive: true);
    } else if (!isDir && File(dst).existsSync()) {
      File(dst).deleteSync();
    }
    try {
      if (isDir) {
        Directory(src).renameSync(dst);
      } else {
        File(src).renameSync(dst);
      }
    } on FileSystemException {
      _copyRecursive(src, dst);
      if (isDir) {
        Directory(src).deleteSync(recursive: true);
      } else {
        File(src).deleteSync();
      }
    }
  }

  static void _copyRecursive(String src, String dst) {
    if (FileSystemEntity.isDirectorySync(src)) {
      Directory(dst).createSync(recursive: true);
      for (final entity in Directory(src).listSync()) {
        _copyRecursive(entity.path, p.join(dst, p.basename(entity.path)));
      }
    } else {
      File(dst).parent.createSync(recursive: true);
      File(src).copySync(dst);
    }
  }
}
