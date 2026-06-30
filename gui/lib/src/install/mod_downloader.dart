import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../mod_registry.dart';

class ModDownloadException implements Exception {
  final String message;
  ModDownloadException(this.message);
  @override
  String toString() => message;
}

/// Downloads a mod zip and places it for the active loader. Ported from the
/// macOS app's ModDownloader, including the Quartz special-casing.
class ModDownloader {
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

    final tmp = Directory(
        p.join(Directory.systemTemp.path, 'adofai_extract_${mod.id}'));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(bodyBytes);
      for (final f in archive) {
        final outPath = p.join(tmp.path, f.name);
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

      if (mod.install == 'quartz') {
        _installQuartz(tmp.path, visible, gameRoot);
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
      final dest = p.join(modsDir, mod.id);
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
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
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
    } finally {
      client.close();
    }
  }

  /// Quartz: MelonLoader build is laid out for the game root (Mods/ + UserData/);
  /// the UMM build is a single mod folder that goes whole into Mods/.
  static void _installQuartz(String extractDir, List<String> visible, String gameRoot) {
    final modsDest = p.join(gameRoot, 'Mods');
    final userDataDest = p.join(gameRoot, 'UserData');
    Directory(modsDest).createSync(recursive: true);
    Directory(userDataDest).createSync(recursive: true);

    if (visible.contains('Mods') || visible.contains('UserData')) {
      if (visible.contains('Mods')) {
        _merge(p.join(extractDir, 'Mods'), modsDest);
      }
      if (visible.contains('UserData')) {
        _merge(p.join(extractDir, 'UserData'), userDataDest);
      }
      return;
    }

    final folder = visible.firstWhere(
      (n) => Directory(p.join(extractDir, n)).existsSync(),
      orElse: () => '',
    );
    if (folder.isEmpty) throw ModDownloadException('Archive was empty');
    _moveInto(p.join(extractDir, folder), p.join(modsDest, folder));
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
