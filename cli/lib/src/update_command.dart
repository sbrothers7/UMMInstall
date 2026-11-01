import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';

/// The binary `amm update` replaces; tests point it elsewhere.
String Function() ammExecutable = () => Platform.resolvedExecutable;

/// Where `amm update` looks for the GUI app; tests point it elsewhere.
List<String> Function() appFolders = () => [
  '/Applications',
  p.join(Platform.environment['HOME'] ?? '/', 'Applications'),
];

const _bundleId = 'com.sbrothers.adofaiModInstaller';

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
/// in an Applications folder with the latest release.
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
  if (Platform.isMacOS) {
    for (final app in _guiApps()) {
      ok &= await _updateGui(c, r, to, app);
    }
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

/// The GUI apps, found by bundle id so a renamed app counts.
List<String> _guiApps() => [
  for (final dir in appFolders())
    if (Directory(dir).existsSync())
      for (final e in Directory(dir).listSync())
        if (e is Directory &&
            e.path.endsWith('.app') &&
            _plist(e.path, 'CFBundleIdentifier') == _bundleId)
          e.path,
];

Future<bool> _updateGui(Ctx c, GithubRelease r, String to, String app) async {
  final from = _plist(app, 'CFBundleShortVersionString') ?? '?';
  if (!isNewerVersion(r.tag, from)) {
    c.out.line('GUI $from is up to date ($app).');
    return true;
  }
  final url = [
    for (final MapEntry(:key, :value) in r.assets.entries)
      if (key.endsWith('-macos.zip')) value,
  ].firstOrNull;
  if (url == null) {
    c.out.log(LogLevel.error, 'Release ${r.tag} has no macOS GUI.');
    return false;
  }
  if (Process.runSync('pgrep', ['-f', '$app/Contents/MacOS/']).exitCode == 0) {
    c.out.log(LogLevel.error, 'Quit the GUI first, then rerun ($app).');
    return false;
  }
  // Beside the app, so the swaps are renames on one disk.
  final work = Directory(p.join(p.dirname(app), '.amm-update-$pid'));
  try {
    work.createSync();
    final zip = File(p.join(work.path, 'gui.zip'))
      ..writeAsBytesSync(await _download(c, 'the GUI', url));
    final out = p.join(work.path, 'new');
    // ditto keeps the bundle's framework symlinks and permissions.
    final x = await Process.run('ditto', ['-x', '-k', zip.path, out]);
    if (x.exitCode != 0) {
      throw _UpdateException('unzip failed: ${(x.stderr as String).trim()}');
    }
    final fresh = Directory(out)
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .firstOrNull;
    if (fresh == null ||
        _plist(fresh.path, 'CFBundleIdentifier') != _bundleId) {
      throw const _UpdateException('no GUI app in the download');
    }
    final old = p.join(work.path, 'old.app');
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
