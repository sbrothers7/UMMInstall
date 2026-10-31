import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'version.dart';

class LatestRelease {
  final String tag;
  final String assetUrl;
  LatestRelease(this.tag, this.assetUrl);
}

/// Cross-platform self-update via GitHub Releases.
///
/// macOS swaps the `.app` bundle; Windows/Linux replace the install directory
/// (a detached helper waits for this process to exit, swaps files, relaunches).
/// The Windows/Linux paths are wired but want real-world testing once the
/// per-platform packaging (release artifacts) is finalized.
class Updater {
  static const repo = 'sbrothers7/UMMInstall';

  static String get currentVersion => appVersion;

  static Future<LatestRelease?> fetchLatest() async {
    try {
      final resp = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 400) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = j['tag_name'] as String?;
      if (tag == null) return null;
      final asset = _selectAsset((j['assets'] as List?) ?? const []);
      if (asset == null) return null;
      return LatestRelease(tag, asset);
    } catch (_) {
      return null;
    }
  }

  /// Picks the .zip asset matching this platform (falls back to the first .zip).
  static String? _selectAsset(List assets) {
    final keys = Platform.isMacOS
        ? const ['macos', 'mac', 'darwin', 'osx']
        : Platform.isWindows
            ? const ['windows', 'win']
            : const ['linux'];
    String? firstZip;
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (!name.endsWith('.zip')) continue;
      firstZip ??= a['browser_download_url'] as String?;
      if (keys.any(name.contains)) return a['browser_download_url'] as String?;
    }
    return firstZip;
  }

  static bool isNewer(String remote, String local) {
    List<int> parts(String s) => s
        .replaceAll(RegExp(r'^[vV\s]+'), '')
        .split('.')
        .map((e) => int.tryParse(RegExp(r'^\d+').stringMatch(e) ?? '') ?? 0)
        .toList();
    final r = parts(remote), l = parts(local);
    final n = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < n; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < l.length ? l[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// The install root to replace: the `.app` on macOS, the executable's
  /// directory on Windows/Linux.
  static String get _appRoot {
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      return p.dirname(p.dirname(p.dirname(exe))); // …/Foo.app/Contents/MacOS/x
    }
    return p.dirname(exe);
  }

  /// True if we can write to the install location (so we don't offer an update
  /// we can't apply — e.g. a read-only/translocated macOS bundle).
  static bool canSelfUpdate() {
    try {
      final probe =
          File(p.join(p.dirname(_appRoot), '.adofai-update-probe-$pid'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> performUpdate(String downloadUrl) async {
    final tmpZip = p.join(Directory.systemTemp.path, 'adofai-update.zip');
    final tmpDir = p.join(Directory.systemTemp.path, 'adofai-update');

    final resp = await http.get(Uri.parse(downloadUrl));
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    await File(tmpZip).writeAsBytes(resp.bodyBytes);

    if (Directory(tmpDir).existsSync()) {
      Directory(tmpDir).deleteSync(recursive: true);
    }
    Directory(tmpDir).createSync(recursive: true);
    await _unzip(tmpZip, tmpDir);

    final newApp = _findNewApp(tmpDir);
    if (newApp == null) throw Exception('Updated app not found in archive.');

    if (Platform.isMacOS) {
      await _swapMac(newApp, tmpZip, tmpDir);
    } else if (Platform.isWindows) {
      await _swapWindows(newApp, tmpZip, tmpDir);
    } else {
      await _swapUnixDir(newApp, tmpZip, tmpDir);
    }
  }

  static Future<void> _unzip(String zip, String dest) async {
    if (Platform.isMacOS) {
      await Process.run('ditto', ['-x', '-k', zip, dest]);
    } else if (Platform.isWindows) {
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Path "$zip" -DestinationPath "$dest" -Force',
      ]);
    } else {
      await Process.run('unzip', ['-o', '-q', zip, '-d', dest]);
    }
  }

  /// macOS: the `.app`. Windows/Linux: the directory containing the executable.
  static String? _findNewApp(String dir) {
    if (Platform.isMacOS) {
      return _findFirst(dir, (e) => e is Directory && e.path.endsWith('.app'));
    }
    final exeName =
        Platform.isWindows ? 'adofai_mod_installer.exe' : 'adofai_mod_installer';
    final exe = _findFirst(
        dir, (e) => e is File && p.basename(e.path) == exeName);
    return exe == null ? null : p.dirname(exe);
  }

  static String? _findFirst(String dir, bool Function(FileSystemEntity) test) {
    for (final e in Directory(dir).listSync(recursive: true)) {
      if (test(e)) return e.path;
    }
    return null;
  }

  static Future<void> _swapMac(String newApp, String tmpZip, String tmpDir) async {
    final helper = p.join(Directory.systemTemp.path, 'adofai-update.sh');
    final script = '''
#!/bin/bash
APP="$_appRoot"
NEW="$newApp"
for _ in \$(seq 1 100); do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
sleep 0.3
rm -rf "\$APP"
mv "\$NEW" "\$APP"
xattr -dr com.apple.quarantine "\$APP" 2>/dev/null || true
open "\$APP"
rm -f "$tmpZip"; rm -rf "$tmpDir"; rm -f "\$0"
''';
    File(helper).writeAsStringSync(script);
    await _runDetached('/bin/bash', [helper]);
  }

  static Future<void> _swapUnixDir(
      String newApp, String tmpZip, String tmpDir) async {
    final helper = p.join(Directory.systemTemp.path, 'adofai-update.sh');
    final script = '''
#!/bin/bash
APP="$_appRoot"
NEW="$newApp"
for _ in \$(seq 1 100); do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
sleep 0.3
cp -af "\$NEW"/. "\$APP"/
chmod +x "\$APP/adofai_mod_installer" 2>/dev/null || true
"\$APP/adofai_mod_installer" &
rm -f "$tmpZip"; rm -rf "$tmpDir"; rm -f "\$0"
''';
    File(helper).writeAsStringSync(script);
    await _runDetached('/bin/bash', [helper]);
  }

  static Future<void> _swapWindows(
      String newApp, String tmpZip, String tmpDir) async {
    final helper = p.join(Directory.systemTemp.path, 'adofai-update.ps1');
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
while (Get-Process -Id $pid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 200 }
Start-Sleep -Milliseconds 500
Copy-Item -Path "$newApp\\*" -Destination "$_appRoot" -Recurse -Force
Start-Process "$_appRoot\\adofai_mod_installer.exe"
Remove-Item "$tmpZip" -Force
Remove-Item "$tmpDir" -Recurse -Force
Remove-Item \$MyInvocation.MyCommand.Path -Force
''';
    File(helper).writeAsStringSync(script);
    await _runDetached(
        'powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', helper]);
  }

  static Future<void> _runDetached(String exe, List<String> args) async {
    await Process.start(exe, args,
        mode: ProcessStartMode.detached, runInShell: false);
  }
}
