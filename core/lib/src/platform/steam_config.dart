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

  static List<String>? _rootsOverride;

  /// Replaces the Steam folders searched (for tests); null restores them.
  static void overrideRoots(List<String>? roots) => _rootsOverride = roots;

  static bool? _runningOverride;

  /// Fakes whether Steam is running (for tests), so [closeSteam] and
  /// [openSteam] flip it instead of touching the real client; null restores.
  static void overrideRunning(bool? running) => _runningOverride = running;

  static List<String> _steamRoots() {
    if (_rootsOverride != null) return _rootsOverride!;
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
    // On Linux ~/.steam/steam and ~/.steam/root are usually links to
    // ~/.local/share/Steam: count each real folder once.
    final seen = <String>{};
    for (final root in _steamRoots()) {
      try {
        if (!seen.add(Directory(root).resolveSymbolicLinksSync())) continue;
      } catch (_) {
        continue;
      }
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
    if (_runningOverride != null) return _runningOverride!;
    try {
      if (Platform.isWindows) {
        final r = Process.runSync('tasklist', const []);
        return (r.stdout as String).toLowerCase().contains('steam.exe');
      }
      // On Linux the client process is named exactly `steam`; a loose match
      // would also catch steamwebhelper and the runtime's helpers, which
      // outlive the client by a moment.
      final r = Process.runSync(
        'pgrep',
        Platform.isLinux ? const ['-x', 'steam'] : const ['-i', 'steam'],
      );
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Asks a running Steam to quit and waits for it to exit. Steam keeps
  /// localconfig.vdf in memory and writes it back on exit, so launch options
  /// edited while it runs are lost. True once Steam is no longer running.
  static Future<bool> closeSteam({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!isSteamRunning()) return true;
    if (_runningOverride != null) {
      _runningOverride = false;
      return true;
    }
    final attempts = Platform.isMacOS
        ? const [
            ['osascript', '-e', 'quit app "Steam"'],
          ]
        : const [
            ['steam', '-shutdown'],
            ['flatpak', 'run', 'com.valvesoftware.Steam', '-shutdown'],
            ['xdg-open', 'steam://exit'],
          ];
    for (final cmd in attempts) {
      try {
        final r = await Process.run(cmd.first, cmd.sublist(1));
        if (r.exitCode == 0) break;
      } catch (_) {}
    }
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!isSteamRunning()) {
        // Let it finish writing its config before we read it.
        await Future<void>.delayed(const Duration(seconds: 2));
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Starts Steam again, detached, after [closeSteam].
  static Future<void> openSteam() async {
    if (_runningOverride != null) {
      _runningOverride = true;
      return;
    }
    final cmd = Platform.isMacOS ? const ['open', '-a', 'Steam'] : const ['steam'];
    try {
      await Process.start(cmd.first, cmd.sublist(1),
          mode: ProcessStartMode.detached);
    } catch (_) {
      if (Platform.isLinux) {
        try {
          await Process.start('xdg-open', const ['steam://open/main'],
              mode: ProcessStartMode.detached);
        } catch (_) {}
      }
    }
  }

  static SteamLaunchOptionsOutcome setLaunchOptions(String setupHelperPath) {
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
      final newText = _apply(text, setupHelperPath);
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
    // No config had a Steam apps block to write into: the user sets it by hand.
    if (updated == 0) return const SteamLaunchOptionsOutcome(noConfig: true);
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

  /// The unescaped Launch Options value for ADOFAI in [vdfText], or null.
  static String? readLaunchOptions(String vdfText) {
    final apps = _steamApps(vdfText);
    if (apps == null) return null;
    final block = _blockRange(vdfText, appId, apps[0], apps[1]);
    if (block == null) return null;
    final vr = _launchOptionsValueRange(vdfText, block[0], block[1]);
    if (vr == null) return null;
    return _unescape(vdfText.substring(vr[0] + 1, vr[1] - 1));
  }

  static String _unescape(String raw) =>
      raw.replaceAllMapped(RegExp(r'\\(["\\])'), (m) => m[1]!);

  static String _escape(String v) =>
      v.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  // A quoted or bare path ending in setup_helper.sh, and the space after it.
  static final _helperRe = RegExp(r'("[^"]*setup_helper\.sh"|\S*setup_helper\.sh)\s*');

  /// [existing] Launch Options with the helper put in front of `%command%`,
  /// keeping the user's own options (env vars before it, args after it).
  static String withHelper(String existing, String setupHelperPath) {
    final rest = withoutHelper(existing);
    final helper = '"$setupHelperPath" %command%';
    if (rest.isEmpty) return helper;
    if (rest.contains('%command%')) {
      return rest.replaceFirst('%command%', helper);
    }
    // Without %command%, Steam appends the options to the game's command line.
    return '$helper $rest';
  }

  /// [existing] Launch Options with the helper taken out; empty when only
  /// `%command%` would be left.
  static String withoutHelper(String existing) {
    final rest = existing.replaceAll(_helperRe, '').trim();
    return rest == '%command%' ? '' : rest;
  }

  /// Whether Launch Options point at setup_helper.sh; null when no
  /// `localconfig.vdf` exists.
  static bool? launchOptionsSet() {
    final paths = localConfigPaths();
    if (paths.isEmpty) return null;
    for (final path in paths) {
      try {
        final v = readLaunchOptions(File(path).readAsStringSync());
        if (v != null && v.contains('setup_helper.sh')) return true;
      } catch (_) {}
    }
    return false;
  }

  // MARK: - Targeted VDF edit

  static String? _apply(String text, String setupHelperPath) {
    final apps = _steamApps(text);
    if (apps == null) return null;
    final escapedValue = _escape(withHelper('', setupHelperPath));
    final block = _blockRange(text, appId, apps[0], apps[1]);
    if (block != null) {
      final vr = _launchOptionsValueRange(text, block[0], block[1]);
      if (vr != null) {
        final old = _unescape(text.substring(vr[0] + 1, vr[1] - 1));
        return text.replaceRange(
            vr[0], vr[1], '"${_escape(withHelper(old, setupHelperPath))}"');
      }
      return text.replaceRange(
          block[0], block[0], '\n\t\t\t\t\t"LaunchOptions"\t\t"$escapedValue"');
    }
    return text.replaceRange(apps[0], apps[0],
        '\n\t\t\t\t"$appId"\n\t\t\t\t{\n\t\t\t\t\t"LaunchOptions"\t\t"$escapedValue"\n\t\t\t\t}');
  }

  /// Takes the helper out of LaunchOptions, leaving the user's own options.
  static String? _clear(String text) {
    final apps = _steamApps(text);
    if (apps == null) return null;
    final block = _blockRange(text, appId, apps[0], apps[1]);
    if (block == null) return null;
    final vr = _launchOptionsValueRange(text, block[0], block[1]);
    if (vr == null) return null;
    final old = _unescape(text.substring(vr[0] + 1, vr[1] - 1));
    if (!old.contains('setup_helper.sh')) return null;
    return text.replaceRange(vr[0], vr[1], '"${_escape(withoutHelper(old))}"');
  }

  /// The body of Software/Valve/Steam/apps, where Launch Options live. The
  /// file has another top-level "apps" block (cloud sync state) that Steam
  /// may write first, so the first "apps" in the file can be the wrong one.
  static List<int>? _steamApps(String s) {
    List<int>? r = [0, s.length];
    for (final key in const ['Software', 'Valve', 'Steam', 'apps']) {
      r = _blockRange(s, key, r![0], r[1]);
      if (r == null) return null;
    }
    return r;
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
