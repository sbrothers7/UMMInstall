import 'dart:io';
import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class LatestRelease {
  final String tag;
  final String assetUrl;
  LatestRelease(this.tag, this.assetUrl);
}

/// Cross-platform self-update via GitHub Releases.
///
/// macOS swaps the `.app` bundle; Windows/Linux replace the install directory
/// (a detached helper waits for this process to exit, swaps files, relaunches).
/// Linux unpacks the release's .tar.gz; the Windows path is wired but has no
/// release artifact yet.
class Updater {
  static String get currentVersion => appVersion;

  /// Linux menu entry name; matches the GTK application id so the window
  /// groups under it. `amm update` finds the GUI through this file.
  static const linuxAppId = 'com.sbrothers.adofai_mod_installer';

  /// Linux: (re)writes the menu entry for this copy, so the app shows up in
  /// the launcher and `amm update` can find it wherever it was unpacked.
  static void writeDesktopEntry() {
    final home = Platform.environment['HOME'];
    if (!Platform.isLinux || home == null) return;
    final data =
        Platform.environment['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share');
    try {
      File(p.join(data, 'applications', '$linuxAppId.desktop'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=ADOFAI Mod Installer
Exec="${Platform.resolvedExecutable}"
Path=$_appRoot
Icon=${p.join(_appRoot, 'icon.png')}
StartupWMClass=$linuxAppId
Categories=Game;Utility;
''');
    } catch (_) {}
  }

  static Future<LatestRelease?> fetchLatest() async {
    try {
      final r = await GithubRelease.latest();
      final asset = r.guiAsset;
      return asset == null ? null : LatestRelease(r.tag, asset);
    } catch (_) {
      return null;
    }
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
    final tmpArchive = p.join(Directory.systemTemp.path,
        Platform.isLinux ? 'adofai-update.tar.gz' : 'adofai-update.zip');
    final tmpDir = p.join(Directory.systemTemp.path, 'adofai-update');

    final resp = await http.get(Uri.parse(downloadUrl));
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    await File(tmpArchive).writeAsBytes(resp.bodyBytes);

    if (Directory(tmpDir).existsSync()) {
      Directory(tmpDir).deleteSync(recursive: true);
    }
    Directory(tmpDir).createSync(recursive: true);
    await _extract(tmpArchive, tmpDir);

    final newApp = _findNewApp(tmpDir);
    if (newApp == null) throw Exception('Updated app not found in archive.');

    if (Platform.isMacOS) {
      await _swapMac(newApp, tmpArchive, tmpDir);
    } else if (Platform.isWindows) {
      await _swapWindows(newApp, tmpArchive, tmpDir);
    } else {
      await _swapUnixDir(newApp, tmpArchive, tmpDir);
    }
  }

  static Future<void> _extract(String archive, String dest) async {
    final r = Platform.isMacOS
        ? await Process.run('ditto', ['-x', '-k', archive, dest])
        : Platform.isWindows
            ? await Process.run('powershell', [
                '-NoProfile',
                '-Command',
                'Expand-Archive -Path "$archive" -DestinationPath "$dest" -Force',
              ])
            : await Process.run('tar', ['-xzf', archive, '-C', dest]);
    if (r.exitCode != 0) throw Exception('Extract failed: ${r.stderr}');
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

  static Future<void> _swapMac(String newApp, String tmpArchive, String tmpDir) async {
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
rm -f "$tmpArchive"; rm -rf "$tmpDir"; rm -f "\$0"
''';
    File(helper).writeAsStringSync(script);
    await _runDetached('/bin/bash', [helper]);
  }

  static Future<void> _swapUnixDir(
      String newApp, String tmpArchive, String tmpDir) async {
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
rm -f "$tmpArchive"; rm -rf "$tmpDir"; rm -f "\$0"
''';
    File(helper).writeAsStringSync(script);
    await _runDetached('/bin/bash', [helper]);
  }

  static Future<void> _swapWindows(
      String newApp, String tmpArchive, String tmpDir) async {
    final helper = p.join(Directory.systemTemp.path, 'adofai-update.ps1');
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
while (Get-Process -Id $pid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 200 }
Start-Sleep -Milliseconds 500
Copy-Item -Path "$newApp\\*" -Destination "$_appRoot" -Recurse -Force
Start-Process "$_appRoot\\adofai_mod_installer.exe"
Remove-Item "$tmpArchive" -Force
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
