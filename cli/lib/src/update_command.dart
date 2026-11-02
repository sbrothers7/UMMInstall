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

/// `amm update`: replaces this amm (ammtui is a link to it) and any GUI app
/// (in an Applications folder, or the Linux copy behind its menu entry) with
/// the latest release.
Future<int> update(Ctx c) async {
  final GithubRelease r;
  try {
    r = await GithubRelease.latest();
  } catch (e) {
    c.out.log(LogLevel.error, "Couldn't check for updates: $e");
    return 1;
  }
  final to = r.tag.replaceFirst(RegExp('^v'), '');
  var ok = await _updateCli(c, r, to);
  for (final app in _guiApps()) {
    ok &= await _updateGui(c, r, to, app);
  }
  return ok ? 0 : 1;
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

Future<bool> _updateCli(Ctx c, GithubRelease r, String to) async {
  final exe = ammExecutable();
  // Under `dart run` the executable is the Dart VM.
  if (!p.basename(exe).startsWith('amm')) {
    c.out.line('Not running an installed amm ($exe); skipping it.');
    return true;
  }
  if (!isNewerVersion(r.tag, appVersion)) {
    c.out.line('amm $appVersion is up to date.');
    return true;
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
  c.out.log(LogLevel.ok, 'amm $appVersion → $to (ammtui too)');
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

Future<bool> _updateGui(Ctx c, GithubRelease r, String to, String app) async {
  final from = _guiVersion(app) ?? '?';
  if (!isNewerVersion(r.tag, from)) {
    c.out.line('GUI $from is up to date ($app).');
    return true;
  }
  final url = r.guiAsset;
  if (url == null) {
    c.out.log(LogLevel.error, 'Release ${r.tag} has no GUI for this system.');
    return false;
  }
  final exe = Platform.isMacOS ? '$app/Contents/MacOS/' : '$app/$_linuxExe';
  if (Process.runSync('pgrep', ['-f', exe]).exitCode == 0) {
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
  c.out.log(LogLevel.ok, 'GUI $from → $to ($app)');
  return true;
}
