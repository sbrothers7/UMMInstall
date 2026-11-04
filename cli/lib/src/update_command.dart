import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';

/// The binary `amm update` replaces; tests point it elsewhere.
String Function() ammExecutable = () => Platform.resolvedExecutable;

/// Where `amm update` looks for the GUI: the Applications folders on macOS,
/// the menu-entry folder the GUI writes to on Linux. Tests point it elsewhere.
List<String> Function() appFolders = () {
  final env = Platform.environment, home = env['HOME'] ?? '/';
  return Platform.isMacOS
      ? ['/Applications', p.join(home, 'Applications')]
      : [
          p.join(
            env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'),
            'applications',
          ),
        ];
};

const _bundleId = 'com.sbrothers.adofaiModInstaller';
// The GUI's Linux menu entry (Updater.linuxAppId) and executable.
const _linuxAppId = 'com.sbrothers.adofai_mod_installer';
const _linuxExe = 'adofai_mod_installer';

/// What the Linux release tarball's folder holds.
const _linuxBundle = {_linuxExe, 'lib', 'data', 'icon.png'};

/// This machine's amm release asset, or null when there is none.
String? ammAsset() => switch (Abi.current()) {
  Abi.macosArm64 => 'amm-darwin-arm64',
  Abi.macosX64 => 'amm-darwin-x64',
  Abi.linuxX64 => 'amm-linux-x64',
  _ => null,
};

class _UpdateException implements Exception {
  final String message;
  const _UpdateException(this.message);
  @override
  String toString() => message;
}

/// The clock automatic updates go by; tests set it.
DateTime Function() clock = DateTime.now;

/// How often amm looks for a release on its own.
const autoUpdateEvery = Duration(days: 1);

/// `amm update`: replaces this amm (the CLI and the TUI are one program) and
/// any GUI app (in an Applications folder, or the Linux copy behind its menu
/// entry) with the latest release.
Future<int> update(Ctx c) async => (await runUpdate(c)).code;

/// [update], also saying whether amm itself was replaced (a running TUI is
/// then the old version). [auto] keeps quiet about what is current and skips
/// an open GUI instead of failing on it.
Future<({int code, bool replacedAmm})> runUpdate(
  Ctx c, {
  GithubRelease? release,
  bool auto = false,
}) async {
  final GithubRelease r;
  try {
    r = release ?? await GithubRelease.latest();
  } catch (e) {
    c.out.log(LogLevel.error, "Couldn't check for updates: $e");
    return (code: 1, replacedAmm: false);
  }
  final to = r.tag.replaceFirst(RegExp('^v'), '');
  final cli = await _updateCli(c, r, to, auto: auto);
  var ok = cli != false;
  for (final app in _guiApps()) {
    ok &= await _updateGui(c, r, to, app, auto: auto);
  }
  return (code: ok ? 0 : 1, replacedAmm: cli == true);
}

bool _isInstalledAmm(String exe) => p.basename(exe).startsWith('amm');

/// The newest release when it is newer than amm or a GUI app, else null.
Future<GithubRelease?> availableUpdate() async {
  final r = await GithubRelease.latest();
  final newer =
      isNewerVersion(r.tag, appVersion) ||
      _guiApps().any((a) => isNewerVersion(r.tag, _guiVersion(a) ?? '0'));
  return newer ? r : null;
}

/// Before a command: at most once per [autoUpdateEvery], updates amm and the
/// GUI when a newer release is out. True when amm was replaced, so the
/// caller can rerun the command on the new version. Never fails the command:
/// being offline just means trying again next time.
Future<bool> autoUpdate(Ctx c) async {
  final cfg = c.config;
  if (!cfg.autoUpdate ||
      Platform.environment.containsKey('AMM_NO_AUTO_UPDATE') ||
      !_isInstalledAmm(ammExecutable())) {
    return false;
  }
  final now = clock(), last = cfg.lastUpdateCheck;
  if (last != null &&
      !now.isBefore(last) &&
      now.difference(last) < autoUpdateEvery) {
    return false;
  }
  cfg.lastUpdateCheck = now;
  try {
    cfg.save();
  } catch (_) {}
  final GithubRelease? r;
  try {
    r = await availableUpdate();
  } catch (_) {
    return false;
  }
  if (r == null) return false;
  c.out.line('Updating to ${r.tag}. (Turn this off with: amm auto-update off)');
  return (await runUpdate(c, release: r, auto: true)).replacedAmm;
}

/// Runs the freshly updated amm with [args] in place of this process and
/// returns its exit code. It skips the update check, as this one just ran.
Future<int> relaunch(List<String> args) async {
  final proc = await Process.start(
    ammExecutable(),
    args,
    mode: ProcessStartMode.inheritStdio,
    environment: {'AMM_NO_AUTO_UPDATE': '1'},
  );
  return proc.exitCode;
}

/// `amm auto-update [on|off]`: shows or sets [Config.autoUpdate].
Future<int> setAutoUpdate(Ctx c, String? value) async {
  if (value == null) {
    c.out.line('Automatic updates are ${c.config.autoUpdate ? 'on' : 'off'}.');
    return 0;
  }
  final on = switch (value) {
    'on' => true,
    'off' => false,
    _ => null,
  };
  if (on == null) {
    c.out.line('Use: amm auto-update on|off');
    return 2;
  }
  c.config
    ..autoUpdate = on
    ..save();
  c.out.log(LogLevel.ok, 'Automatic updates turned $value.');
  return 0;
}

Future<List<int>> _download(Ctx c, String what, String url) async {
  c.out.progress('Downloading $what', null);
  try {
    final uri = Uri.parse(url);
    final resp = await httpClient.get(uri).timeout(const Duration(minutes: 5));
    if (resp.statusCode >= 400) {
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    }
    return resp.bodyBytes;
  } finally {
    c.out.clearProgress();
  }
}

/// True when amm was replaced, null when there was nothing to do, false on
/// failure.
Future<bool?> _updateCli(
  Ctx c,
  GithubRelease r,
  String to, {
  bool auto = false,
}) async {
  final exe = ammExecutable();
  // Under `dart run` the executable is the Dart VM.
  if (!_isInstalledAmm(exe)) {
    if (!auto) c.out.line('Not running an installed amm ($exe); skipping it.');
    return null;
  }
  if (!isNewerVersion(r.tag, appVersion)) {
    if (!auto) c.out.line('amm $appVersion is up to date.');
    return null;
  }
  final url = r.assets[ammAsset()];
  if (url == null) {
    c.out.log(LogLevel.error, 'Release ${r.tag} has no amm for this machine.');
    return false;
  }
  // Beside the binary, so the swap is a rename on one disk.
  final tmp = File(p.join(p.dirname(exe), '.amm-update-$pid'));
  try {
    tmp.writeAsBytesSync(await _download(c, 'amm', url));
    await Process.run('chmod', ['755', tmp.path]);
    // A truncated or wrong download must not replace a working amm.
    if ((await Process.run(tmp.path, ['help'])).exitCode != 0) {
      throw const _UpdateException("the download doesn't run");
    }
    tmp.renameSync(exe);
  } catch (e) {
    c.out.log(LogLevel.error, "Couldn't update amm: $e");
    return false;
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
  c.out.log(LogLevel.ok, 'Updated amm $appVersion → $to (CLI and TUI)');
  return true;
}

String? _plist(String app, String key) {
  final r = Process.runSync('plutil', [
    '-extract',
    key,
    'raw',
    p.join(app, 'Contents', 'Info.plist'),
  ]);
  return r.exitCode == 0 ? (r.stdout as String).trim() : null;
}

/// Whether [path] is the GUI: its bundle id on macOS (so a renamed app
/// counts), its executable on Linux.
bool _isGui(String path) => Platform.isMacOS
    ? _plist(path, 'CFBundleIdentifier') == _bundleId
    : File(p.join(path, _linuxExe)).existsSync();

/// The GUI's version: Info.plist on macOS, Flutter's version.json on Linux.
String? _guiVersion(String app) {
  if (Platform.isMacOS) return _plist(app, 'CFBundleShortVersionString');
  try {
    final f = File(p.join(app, 'data', 'flutter_assets', 'version.json'));
    return (jsonDecode(f.readAsStringSync()) as Map)['version'] as String?;
  } catch (_) {
    return null;
  }
}

/// The folder a Linux menu entry runs the GUI from (its `Path=`), or null.
String? _entryPath(File entry) {
  if (!entry.existsSync()) return null;
  for (final line in entry.readAsLinesSync()) {
    if (line.startsWith('Path=')) return line.substring(5);
  }
  return null;
}

/// The GUI installs: .app bundles on macOS; on Linux, the copy the GUI's menu
/// entry points at (it rewrites the entry on each launch).
List<String> _guiApps() => [
  for (final dir in appFolders())
    if (Platform.isMacOS) ...[
      if (Directory(dir).existsSync())
        for (final e in Directory(dir).listSync())
          if (e is Directory && e.path.endsWith('.app') && _isGui(e.path))
            e.path,
    ] else if (_entryPath(File(p.join(dir, '$_linuxAppId.desktop')))
        case final app? when _isGui(app))
      app,
];

Future<bool> _updateGui(
  Ctx c,
  GithubRelease r,
  String to,
  String app, {
  bool auto = false,
}) async {
  final from = _guiVersion(app) ?? '?';
  if (!isNewerVersion(r.tag, from)) {
    if (!auto) c.out.line('GUI $from is up to date ($app).');
    return true;
  }
  final url = r.guiAsset;
  if (url == null) {
    c.out.log(LogLevel.error, 'Release ${r.tag} has no GUI for this system.');
    return false;
  }
  final exe = Platform.isMacOS ? '$app/Contents/MacOS/' : '$app/$_linuxExe';
  if (Process.runSync('pgrep', ['-f', exe]).exitCode == 0) {
    if (auto) {
      // The GUI offers the update itself on its next launch.
      c.out.line('The GUI is open, so it was left at $from.');
      return true;
    }
    c.out.log(LogLevel.error, 'Quit the GUI first, then rerun ($app).');
    return false;
  }
  // The menu entry can point at a folder the user shares with other files;
  // the swap below replaces the whole folder, so only touch the app's own.
  if (Platform.isLinux) {
    final extra = [
      for (final e in Directory(app).listSync())
        if (!_linuxBundle.contains(p.basename(e.path))) p.basename(e.path),
    ];
    if (extra.isNotEmpty) {
      c.out.log(
        LogLevel.error,
        'Not replacing $app: it also holds ${extra.take(3).join(', ')}. '
        'Unpack the GUI into its own folder, then rerun.',
      );
      return false;
    }
  }
  // Beside the app, so the swaps are renames on one disk.
  final work = Directory(p.join(p.dirname(app), '.amm-update-$pid'));
  try {
    work.createSync();
    final archive = File(p.join(work.path, 'gui'))
      ..writeAsBytesSync(await _download(c, 'the GUI', url));
    final out = Directory(p.join(work.path, 'new'))..createSync();
    // ditto keeps the bundle's framework symlinks; tar the executable bit.
    final x = Platform.isMacOS
        ? await Process.run('ditto', ['-x', '-k', archive.path, out.path])
        : await Process.run('tar', ['-xzf', archive.path, '-C', out.path]);
    if (x.exitCode != 0) {
      throw _UpdateException('unpack failed: ${(x.stderr as String).trim()}');
    }
    final fresh = out
        .listSync()
        .whereType<Directory>()
        .where((d) => _isGui(d.path))
        .firstOrNull;
    if (fresh == null) {
      throw const _UpdateException('no GUI app in the download');
    }
    final old = p.join(work.path, 'old');
    Directory(app).renameSync(old);
    try {
      fresh.renameSync(app);
    } catch (_) {
      Directory(old).renameSync(app);
      rethrow;
    }
  } catch (e) {
    c.out.log(LogLevel.error, "Couldn't update the GUI ($app): $e");
    return false;
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
  c.out.log(LogLevel.ok, 'Updated the GUI $from → $to ($app)');
  return true;
}
