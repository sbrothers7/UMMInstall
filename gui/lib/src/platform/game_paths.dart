import 'dart:io';
import 'package:path/path.dart' as p;

/// Locates the ADOFAI install and loader state per platform.
///
/// [detect] runs the async discovery (registry / Steam library folders) once at
/// startup and caches the result; the sync getters read the cache.
class GamePaths {
  static const _gameDirName = 'A Dance of Fire and Ice';
  static const _gameExeWindows = 'A Dance of Fire and Ice.exe';

  static String? _cachedGamePath;

  static String get _home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';

  /// Discovers the game directory across Steam libraries. Call once at startup.
  static Future<void> detect() async {
    _cachedGamePath = await _detectGamePath();
  }

  static String get gamePath => _cachedGamePath ?? _defaultGamePath;

  /// Best-guess default used before [detect] runs or if discovery fails.
  static String get _defaultGamePath {
    if (Platform.isMacOS) {
      return p.join(_home, 'Library/Application Support/Steam', 'steamapps',
          'common', _gameDirName);
    }
    if (Platform.isWindows) {
      return p.join(r'C:\Program Files (x86)\Steam', 'steamapps', 'common',
          _gameDirName);
    }
    return p.join(_home, '.steam/steam', 'steamapps', 'common', _gameDirName);
  }

  // MARK: - Discovery

  static Future<String?> _detectGamePath() async {
    if (Platform.isMacOS) {
      return Directory(_defaultGamePath).existsSync() ? _defaultGamePath : null;
    }
    if (Platform.isWindows) return _detectWindows();
    return _detectLinux();
  }

  static Future<String?> _detectWindows() async {
    final steam = await _windowsSteamPath();
    if (steam == null) return null;
    for (final lib in _steamLibraries(steam)) {
      final candidate = p.join(lib, 'steamapps', 'common', _gameDirName);
      if (File(p.join(candidate, _gameExeWindows)).existsSync()) return candidate;
    }
    return null;
  }

  static Future<String?> _detectLinux() async {
    final roots = <String>[
      p.join(_home, '.steam/steam'),
      p.join(_home, '.local/share/Steam'),
      p.join(_home, '.steam/root'),
      p.join(_home, '.steam/debian-installation'),
      p.join(_home, '.var/app/com.valvesoftware.Steam/.local/share/Steam'),
    ];
    for (final root in roots) {
      if (!Directory(root).existsSync()) continue;
      for (final lib in _steamLibraries(root)) {
        final candidate = p.join(lib, 'steamapps', 'common', _gameDirName);
        if (Directory(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  static Future<String?> _windowsSteamPath() async {
    const queries = [
      [r'HKCU\Software\Valve\Steam', 'SteamPath'],
      [r'HKLM\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'],
      [r'HKLM\SOFTWARE\Valve\Steam', 'InstallPath'],
    ];
    for (final q in queries) {
      final v = await _regQuery(q[0], q[1]);
      if (v != null && Directory(v).existsSync()) return v;
    }
    const def = r'C:\Program Files (x86)\Steam';
    return Directory(def).existsSync() ? def : null;
  }

  static Future<String?> _regQuery(String key, String value) async {
    try {
      final r = await Process.run('reg', ['query', key, '/v', value]);
      if (r.exitCode != 0) return null;
      final m = RegExp('$value' r'\s+REG_\w+\s+(.+)')
          .firstMatch((r.stdout as String));
      if (m != null) return m.group(1)!.trim().replaceAll('/', r'\');
    } catch (_) {}
    return null;
  }

  /// Parses libraryfolders.vdf (same format on all platforms) for extra
  /// library roots, plus the Steam root itself.
  static List<String> _steamLibraries(String steamRoot) {
    final libs = <String>[steamRoot];
    final vdf = File(p.join(steamRoot, 'steamapps', 'libraryfolders.vdf'));
    if (vdf.existsSync()) {
      final re = RegExp(r'"(?:path|\d+)"\s+"(.+?)"');
      for (final line in vdf.readAsLinesSync()) {
        final m = re.firstMatch(line);
        if (m != null) libs.add(m.group(1)!.replaceAll(r'\\', r'\'));
      }
    }
    return libs;
  }

  // MARK: - Paths derived from the game directory

  static String get gameAppPath => p.join(gamePath, 'ADanceOfFireAndIce.app');

  static String get _managedDir {
    if (Platform.isMacOS) {
      return p.join(gameAppPath, 'Contents/Resources/Data/Managed');
    }
    return p.join(gamePath, 'A Dance of Fire and Ice_Data', 'Managed');
  }

  static String get ummModsPath => p.join(gamePath, 'Mods');
  static String get melonModsPath => p.join(gamePath, 'UMMMods');

  /// Persistent soft-delete archive (a dot-folder the game won't load).
  static String get archivePath => p.join(gamePath, '.adofai-archive');

  static bool hasMelonLoader() =>
      Directory(p.join(gamePath, 'MelonLoader')).existsSync();

  static bool isUMMInstalled() =>
      File(p.join(_managedDir, 'UnityModManager', 'UnityModManager.dll'))
          .existsSync();

  static bool gameExists() {
    if (Platform.isMacOS) return Directory(gameAppPath).existsSync();
    return Directory(gamePath).existsSync();
  }

  static bool isAppleSilicon() {
    if (!Platform.isMacOS) return false;
    try {
      final r = Process.runSync('sysctl', ['-n', 'hw.optional.arm64']);
      return (r.stdout as String).trim() == '1';
    } catch (_) {
      return false;
    }
  }

  /// Whether the game binary still has its arm64 slice. A previous v2 UMM
  /// install on Apple Silicon strips it (for Rosetta); the v3 native loader
  /// then needs the user to verify game files in Steam to restore it.
  static bool hasArm64Slice() {
    if (!Platform.isMacOS) return true;
    final exe = p.join(gameAppPath, 'Contents/MacOS/ADanceOfFireAndIce');
    if (!File(exe).existsSync()) return true; // can't tell — assume fine
    try {
      final r = Process.runSync('lipo', ['-info', exe]);
      return (r.stdout as String).contains('arm64');
    } catch (_) {
      return true;
    }
  }

  /// Reads CFBundleShortVersionString on macOS; null elsewhere for now.
  static Future<String?> detectGameVersion() async {
    if (Platform.isMacOS) {
      final plist = p.join(gameAppPath, 'Contents/Info.plist');
      if (!File(plist).existsSync()) return null;
      try {
        final r = await Process.run('/usr/libexec/PlistBuddy',
            ['-c', 'Print :CFBundleShortVersionString', plist]);
        if (r.exitCode == 0) {
          final v = (r.stdout as String).trim();
          return v.isEmpty ? null : v;
        }
      } catch (_) {}
      return null;
    }
    // TODO: Windows/Linux version detection.
    return null;
  }
}
