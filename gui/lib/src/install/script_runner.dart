import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models.dart';

/// Downloads a per-OS install script and runs it, streaming its output into the
/// log. Mirrors the macOS app's ScriptRunner: scripts emit `info:`/`ok:`/
/// `error:`/`detail:`/`subtitle:` prefixed lines that we route accordingly.
class ScriptRunner {
  static final _progress =
      RegExp(r'^[#\s]*\d{1,3}(\.\d+)?%[#\s]*$|^#{3,}\s*$');

  static Future<int> run({
    required String url,
    required void Function(LogLevel, String) onLog,
    required void Function(String) onSubtitle,
  }) async {
    final isPs = Platform.isWindows;
    final ext = isPs ? 'ps1' : 'sh';
    final tmp = p.join(Directory.systemTemp.path,
        'adofai-script-${DateTime.now().millisecondsSinceEpoch}.$ext');

    try {
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 400) {
        onLog(LogLevel.error, 'Failed to download script (HTTP ${resp.statusCode}).');
        return -1;
      }
      await File(tmp).writeAsBytes(resp.bodyBytes);
    } catch (e) {
      onLog(LogLevel.error, 'Failed to download script.');
      onLog(LogLevel.detail, e.toString());
      return -1;
    }

    Process proc;
    try {
      if (isPs) {
        proc = await Process.start('powershell',
            ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tmp]);
      } else {
        proc = await Process.start('/bin/bash', [tmp]);
      }
    } catch (e) {
      onLog(LogLevel.error, 'Failed to start script.');
      onLog(LogLevel.detail, e.toString());
      _tryDelete(tmp);
      return -1;
    }

    void handle(String raw) {
      var line = raw;
      // Collapse carriage-return animations to the final visible segment.
      if (line.contains('\r')) {
        final segs = line.split('\r').where((s) => s.isNotEmpty);
        line = segs.isEmpty ? '' : segs.last;
      }
      line = line.trim();
      if (line.isEmpty) return;
      if (_progress.hasMatch(line)) return; // drop progress meters

      final colon = line.indexOf(':');
      if (colon > 0) {
        final prefix = line.substring(0, colon).toLowerCase();
        final body = line.substring(colon + 1);
        switch (prefix) {
          case 'info':
            onLog(LogLevel.info, body);
            return;
          case 'ok':
            onLog(LogLevel.ok, body);
            return;
          case 'error':
            onLog(LogLevel.error, body);
            return;
          case 'detail':
            onLog(LogLevel.detail, body);
            return;
          case 'subtitle':
            onSubtitle(body);
            return;
          case 'complete':
          case 'failed':
            return;
        }
      }
      onLog(LogLevel.info, line);
    }

    final outDone = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(handle);
    final errDone = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(handle);

    final code = await proc.exitCode;
    await Future.wait([outDone, errDone]);
    _tryDelete(tmp);
    return code;
  }

  static void _tryDelete(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}
