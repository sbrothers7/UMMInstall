import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../mod_registry.dart';
import '../net.dart';

class ModDownloadException implements Exception {
  final String message;
  ModDownloadException(this.message);
  @override
  String toString() => message;
}

/// Downloads a mod zip and places it for the active loader. Ported from the
/// macOS app's ModDownloader.
class ModDownloader {
  /// MelonLoader's folders in the game root. A zip whose top level has any of
  /// these is laid out for the game root (e.g. `Mods/x.dll` + `UserLibs/`) and
  /// is merged there rather than wrapped as a single mod folder.
  static const _gameRootDirs = {'Mods', 'Plugins', 'UserData', 'UserLibs'};

  static Future<void> install({
    required Mod mod,
    required bool isGameV2,
    required bool isMelonLoader,
    required String gameRoot,
    required String modsDir,
    void Function(double fraction)? onProgress,
  }) async {
    final url = mod.resolvedUrl(isGameV2: isGameV2, isMelonLoader: isMelonLoader);
    final bodyBytes = await _download(url, onProgress);
    installBytes(bodyBytes, modId: mod.id, gameRoot: gameRoot, modsDir: modsDir);
  }

  /// Extracts a downloaded zip and places it. Split from [install] for tests.
  static void installBytes(
    List<int> bodyBytes, {
    required String modId,
    required String gameRoot,
    required String modsDir,
  }) {
    final tmp = Directory(
        p.join(Directory.systemTemp.path, 'adofai_extract_$modId'));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(bodyBytes);
      for (final f in archive) {
        if (f.isSymbolicLink) continue;
        // Reject entries like `../x` or `/abs/x` that would land outside tmp.
        final outPath = p.normalize(p.join(tmp.path, f.name));
        if (!p.isWithin(tmp.path, outPath)) {
          if (p.equals(tmp.path, outPath)) continue; // a `./` entry
          throw ModDownloadException('Unsafe path in archive: ${f.name}');
        }
        if (f.isFile) {
          File(outPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(f.content as List<int>);
        } else {
          Directory(outPath).createSync(recursive: true);
        }
      }

      final visible = tmp
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => !n.startsWith('.') && n != '__MACOSX')
          .toList();
      if (visible.isEmpty) throw ModDownloadException('Archive was empty');

      // Game-root layout (MelonLoader builds such as Quartz and
      // EnhancedEffectRemover_ML) → merge each folder into the game root.
      final rootDirs = visible.where((n) =>
          _gameRootDirs.contains(n) &&
          Directory(p.join(tmp.path, n)).existsSync());
      if (rootDirs.isNotEmpty) {
        for (final d in rootDirs) {
          _merge(p.join(tmp.path, d), p.join(gameRoot, d));
        }
        return;
      }

      Directory(modsDir).createSync(recursive: true);

      // Single top-level folder → move it whole into the mods dir.
      if (visible.length == 1 &&
          Directory(p.join(tmp.path, visible.first)).existsSync()) {
        _moveInto(p.join(tmp.path, visible.first), p.join(modsDir, visible.first));
        return;
      }

      // Loose files → wrap them in a folder named after the mod.
      final dest = p.join(modsDir, modId);
      if (Directory(dest).existsSync()) Directory(dest).deleteSync(recursive: true);
      Directory(dest).createSync(recursive: true);
      for (final item in visible) {
        _moveInto(p.join(tmp.path, item), p.join(dest, item));
      }
    } finally {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Streams the download so we can report progress. Falls back to an
  /// indeterminate bar (onProgress never reports a fraction) when the server
  /// doesn't send a Content-Length.
  static Future<Uint8List> _download(
      String url, void Function(double)? onProgress) async {
    final resp = await httpClient.send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode >= 400) {
      throw ModDownloadException('HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength ?? 0;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in resp.stream) {
      builder.add(chunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) onProgress(received / total);
    }
    return builder.takeBytes();
  }

  /// Moves each top-level child of [src] into [dst], replacing existing entries.
  static void _merge(String src, String dst) {
    Directory(dst).createSync(recursive: true);
    for (final entity in Directory(src).listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      _moveInto(entity.path, p.join(dst, name));
    }
  }

  /// Moves a file or directory to [dst] (replacing it), handling cross-volume
  /// moves by falling back to copy + delete.
  static void _moveInto(String src, String dst) {
    final isDir = FileSystemEntity.isDirectorySync(src);
    if (isDir) {
      if (Directory(dst).existsSync()) Directory(dst).deleteSync(recursive: true);
    } else if (File(dst).existsSync()) {
      File(dst).deleteSync();
    }
    try {
      if (isDir) {
        Directory(src).renameSync(dst);
      } else {
        File(src).renameSync(dst);
      }
    } on FileSystemException {
      // Cross-device: copy then remove the source.
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
