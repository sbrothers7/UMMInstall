import 'dart:io';
import 'package:path/path.dart' as p;

class SteamLaunchOptionsOutcome {
  final int updated;
  final bool steamRunning;
  final bool noConfig;
  final String? error;
  const SteamLaunchOptionsOutcome({
    this.updated = 0,
    this.steamRunning = false,
    this.noConfig = false,
    this.error,
  });
}

/// Sets/clears the per-user Steam Launch Options for ADOFAI (appid 977950) by a
/// targeted edit of each `userdata/<id>/config/localconfig.vdf`. Ported from the
/// macOS Swift implementation (brace-matched, backed up, byte-preserving).
///
/// Not needed on Windows (MelonLoader injects via a proxy version.dll there).
class SteamConfig {
  static const appId = '977950';

  static String get _home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';

  static List<String> _steamRoots() {
    if (Platform.isMacOS) {
      return [p.join(_home, 'Library/Application Support/Steam')];
    }
    if (Platform.isLinux) {
      return [
        p.join(_home, '.steam/steam'),
        p.join(_home, '.local/share/Steam'),
        p.join(_home, '.steam/root'),
        p.join(_home, '.var/app/com.valvesoftware.Steam/.local/share/Steam'),
      ];
    }
    return const [];
  }

  static List<String> localConfigPaths() {
    final result = <String>[];
    for (final root in _steamRoots()) {
      final userdata = Directory(p.join(root, 'userdata'));
      if (!userdata.existsSync()) continue;
      for (final id in userdata.listSync()) {
        if (id is! Directory) continue;
        final cfg = p.join(id.path, 'config', 'localconfig.vdf');
        if (File(cfg).existsSync()) result.add(cfg);
      }
    }
    return result;
  }

  static bool isSteamRunning() {
    try {
      if (Platform.isWindows) {
        final r = Process.runSync('tasklist', const []);
        return (r.stdout as String).toLowerCase().contains('steam.exe');
      }
      final r = Process.runSync('pgrep', const ['-i', 'steam']);
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static SteamLaunchOptionsOutcome setLaunchOptions(String setupHelperPath) {
    final paths = localConfigPaths();
    if (paths.isEmpty) return const SteamLaunchOptionsOutcome(noConfig: true);

    final raw = '"$setupHelperPath" %command%';
    final escaped = raw.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

    var updated = 0;
    for (final path in paths) {
      String text;
      try {
        text = File(path).readAsStringSync();
      } catch (_) {
        continue;
      }
      final newText = _apply(text, escaped);
      if (newText == null) continue;
      if (newText == text) {
        updated++;
        continue;
      }
      try {
        File('$path.adofai.bak').writeAsStringSync(text);
        File(path).writeAsStringSync(newText);
        updated++;
      } catch (e) {
        return SteamLaunchOptionsOutcome(error: e.toString());
      }
    }
    return SteamLaunchOptionsOutcome(updated: updated, steamRunning: isSteamRunning());
  }

  static SteamLaunchOptionsOutcome clearLaunchOptions() {
    final paths = localConfigPaths();
    if (paths.isEmpty) return const SteamLaunchOptionsOutcome(noConfig: true);

    var updated = 0;
    for (final path in paths) {
      String text;
      try {
        text = File(path).readAsStringSync();
      } catch (_) {
        continue;
      }
      final newText = _clear(text);
      if (newText == null || newText == text) continue;
      try {
        File('$path.adofai.bak').writeAsStringSync(text);
        File(path).writeAsStringSync(newText);
        updated++;
      } catch (e) {
        return SteamLaunchOptionsOutcome(error: e.toString());
      }
    }
    return SteamLaunchOptionsOutcome(updated: updated, steamRunning: isSteamRunning());
  }

  // MARK: - Targeted VDF edit

  static String? _apply(String text, String escapedValue) {
    final apps = _blockRange(text, 'apps', 0, text.length);
    if (apps == null) return null;
    final block = _blockRange(text, appId, apps[0], apps[1]);
    if (block != null) {
      final vr = _launchOptionsValueRange(text, block[0], block[1]);
      if (vr != null) {
        return text.replaceRange(vr[0], vr[1], '"$escapedValue"');
      }
      return text.replaceRange(
          block[0], block[0], '\n\t\t\t\t\t"LaunchOptions"\t\t"$escapedValue"');
    }
    return text.replaceRange(apps[0], apps[0],
        '\n\t\t\t\t"$appId"\n\t\t\t\t{\n\t\t\t\t\t"LaunchOptions"\t\t"$escapedValue"\n\t\t\t\t}');
  }

  /// Blanks our LaunchOptions if it still references setup_helper.sh (so a
  /// user's own custom option is left alone).
  static String? _clear(String text) {
    final apps = _blockRange(text, 'apps', 0, text.length);
    if (apps == null) return null;
    final block = _blockRange(text, appId, apps[0], apps[1]);
    if (block == null) return null;
    final vr = _launchOptionsValueRange(text, block[0], block[1]);
    if (vr == null) return null;
    if (!text.substring(vr[0], vr[1]).contains('setup_helper.sh')) return null;
    return text.replaceRange(vr[0], vr[1], '""');
  }

  static int _lc(int c) => (c >= 65 && c <= 90) ? c + 32 : c;
  static bool _ws(int c) => c == 32 || c == 9 || c == 10 || c == 13;

  /// Finds `"key"` (case-insensitive) within [lo,hi) followed by a `{…}` block;
  /// returns [bodyStart, bodyEnd) (exclusive of the braces).
  static List<int>? _blockRange(String s, String key, int lo, int hi) {
    final needle = '"$key"';
    final n = needle.length;
    var i = lo;
    while (i <= hi - n) {
      if (s.codeUnitAt(i) == 34) {
        var k = 0;
        while (k < n && _lc(s.codeUnitAt(i + k)) == _lc(needle.codeUnitAt(k))) {
          k++;
        }
        if (k == n) {
          var j = i + n;
          while (j < s.length && _ws(s.codeUnitAt(j))) {
            j++;
          }
          if (j < s.length && s.codeUnitAt(j) == 123) {
            final body = _matchBraces(s, j);
            if (body != null) return body;
          }
        }
      }
      i++;
    }
    return null;
  }

  static List<int>? _matchBraces(String s, int openBrace) {
    final bodyStart = openBrace + 1;
    var depth = 1, j = bodyStart;
    while (j < s.length) {
      final c = s.codeUnitAt(j);
      if (c == 34) {
        j = _skipQuoted(s, j);
        continue;
      }
      if (c == 123) {
        depth++;
      } else if (c == 125) {
        depth--;
        if (depth == 0) return [bodyStart, j];
      }
      j++;
    }
    return null;
  }

  static List<int>? _launchOptionsValueRange(String s, int lo, int hi) {
    const needle = '"launchoptions"';
    final n = needle.length;
    var i = lo;
    while (i <= hi - n) {
      if (s.codeUnitAt(i) == 34) {
        var k = 0;
        while (k < n && _lc(s.codeUnitAt(i + k)) == needle.codeUnitAt(k)) {
          k++;
        }
        if (k == n) {
          var v = i + n;
          while (v < hi && (s.codeUnitAt(v) == 32 || s.codeUnitAt(v) == 9)) {
            v++;
          }
          if (v < hi && s.codeUnitAt(v) == 34) {
            return [v, _skipQuoted(s, v)];
          }
          return null;
        }
      }
      i++;
    }
    return null;
  }

  static int _skipQuoted(String s, int openQuote) {
    var i = openQuote + 1;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 92) {
        i += 2;
        continue;
      }
      if (c == 34) return i + 1;
      i++;
    }
    return i;
  }
}
