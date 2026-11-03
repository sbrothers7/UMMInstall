import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../mod_registry.dart';
import '../mod_store.dart';
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

  /// Downloads and places [mod]; returns the absolute paths it placed.
  static Future<List<String>> install({
    required Mod mod,
    required bool isGameV2,
    required bool isMelonLoader,
    required String gameRoot,
    required String modsDir,
    void Function(double fraction)? onProgress,
  }) async {
    final url = mod.resolvedUrl(isGameV2: isGameV2, isMelonLoader: isMelonLoader);
    final bodyBytes = await download(url, onProgress: onProgress);
    return installBytes(bodyBytes, modId: mod.id, gameRoot: gameRoot, modsDir: modsDir);
  }

  /// Extracts a downloaded zip and places it, returning the absolute path of
  /// each top-level item placed. Split from [install] for tests. With
  /// [melonNative], loose files go straight into [modsDir] instead of a folder.
  /// [modId] names folders, so it must be a single path segment.
  static List<String> installBytes(
    List<int> bodyBytes, {
    required String modId,
    required String gameRoot,
    required String modsDir,
    bool melonNative = false,
  }) {
    if (modId.isEmpty || modId == '.' || modId == '..' || modId != p.basename(modId)) {
      throw ModDownloadException('Bad mod id: $modId');
    }
    final tmp = Directory(
        p.join(Directory.systemTemp.path, 'adofai_extract_$modId'));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      // Entries are decoded lazily, so a bad archive can throw in the loop.
      try {
        final archive = ZipDecoder().decodeBytes(bodyBytes);
        // A body that isn't a zip at all decodes to nothing.
        if (archive.isEmpty) throw const FormatException('no entries');
        for (final f in archive) {
          if (f.isSymbolicLink) continue;
          // Windows tools write `\` separators. Reject entries like `../x` or
          // `/abs/x` that would land outside tmp.
          final outPath =
              p.normalize(p.join(tmp.path, f.name.replaceAll(r'\', '/')));
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
      } on FormatException catch (e) {
        // Also catches ArchiveException, a FormatException.
        throw ModDownloadException('Not a valid zip: ${e.message}');
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
        return [
          for (final d in rootDirs)
            ..._merge(p.join(tmp.path, d), p.join(gameRoot, d)),
        ];
      }

      Directory(modsDir).createSync(recursive: true);

      // Single top-level folder → move it whole into the mods dir.
      if (visible.length == 1 &&
          Directory(p.join(tmp.path, visible.first)).existsSync()) {
        ModStore.moveEntity(p.join(tmp.path, visible.first), p.join(modsDir, visible.first));
        return [p.join(modsDir, visible.first)];
      }

      // Loose files for a MelonLoader-native mod → straight into the mods dir.
      if (melonNative) {
        for (final item in visible) {
          ModStore.moveEntity(p.join(tmp.path, item), p.join(modsDir, item));
        }
        return [for (final item in visible) p.join(modsDir, item)];
      }

      // Loose files → wrap them in a folder named after the mod.
      final dest = p.join(modsDir, modId);
      if (Directory(dest).existsSync()) Directory(dest).deleteSync(recursive: true);
      Directory(dest).createSync(recursive: true);
      for (final item in visible) {
        ModStore.moveEntity(p.join(tmp.path, item), p.join(dest, item));
      }
      return [dest];
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
  /// doesn't send a Content-Length. An error body's `statusMessage` (as
  /// modlist.org sends) is added to the exception. Transport failures become
  /// a [ModDownloadException] too.
  static Future<Uint8List> download(String url,
      {void Function(double)? onProgress}) async {
    try {
      final resp = await httpClient.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode >= 400) {
        String? msg;
        try {
          msg = (jsonDecode(await resp.stream.bytesToString())
              as Map<String, dynamic>)['statusMessage'] as String?;
        } catch (_) {}
        throw ModDownloadException(
            'HTTP ${resp.statusCode}${msg == null ? '' : ': $msg'}');
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
    } on Exception catch (e) {
      final msg = switch (e) {
        http.ClientException(:final message) => message,
        SocketException(:final message) => message,
        HandshakeException(:final message) => message,
        TimeoutException(:final message) => message ?? 'timed out',
        _ => null,
      };
      if (msg == null) rethrow;
      throw ModDownloadException('Download failed: $msg');
    }
  }

  /// Moves each top-level child of [src] into [dst], replacing existing entries;
  /// returns the destination paths.
  static List<String> _merge(String src, String dst) {
    Directory(dst).createSync(recursive: true);
    final placed = <String>[];
    for (final entity in Directory(src).listSync()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      ModStore.moveEntity(entity.path, p.join(dst, name));
      placed.add(p.join(dst, name));
    }
    return placed;
  }
}
