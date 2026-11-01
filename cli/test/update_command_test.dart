import 'dart:convert';
import 'dart:io';

import 'package:amm/src/update_command.dart';
import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const runs = '#!/bin/sh\nexit 0\n';
const id = 'com.sbrothers.adofaiModInstaller';
final notMac = Platform.isMacOS ? false : 'the GUI is macOS only';

void main() {
  late TestEnv env;
  late File bin;
  setUp(() {
    env = testEnv();
    bin = File('${env.tmp.path}/bin/amm')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    final exe = ammExecutable, apps = appFolders;
    ammExecutable = () => bin.path;
    appFolders = () => ['${env.tmp.path}/Apps', '${env.tmp.path}/none'];
    addTearDown(() {
      ammExecutable = exe;
      appFolders = apps;
    });
  });

  /// Serves a release [tag] with [files] as its assets.
  void release(String tag, Map<String, List<int>> files) {
    httpClient = MockClient((req) async {
      if (req.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode({
            'tag_name': tag,
            'assets': [
              for (final n in files.keys)
                {'name': n, 'browser_download_url': 'https://dl/$n'},
            ],
          }),
          200,
        );
      }
      final f = files[req.url.pathSegments.last];
      return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
    });
  }

  List<String> leftovers(String dir) => [
    for (final e in Directory(dir).listSync())
      if (e.path.contains('.amm-update')) e.path,
  ];

  test('update replaces amm with a newer release', () async {
    release('v99.0.0', {ammAsset()!: utf8.encode(runs)});
    expect(await update(env.ctx()), 0);
    expect(bin.readAsStringSync(), runs);
    expect(bin.statSync().mode & 0x40, isNot(0), reason: 'owner can run it');
    expect(env.sink.toString(), contains('amm $appVersion → 99.0.0'));
    expect(leftovers(bin.parent.path), isEmpty);
  });

  test('update leaves a current amm alone', () async {
    release('v$appVersion', {ammAsset()!: utf8.encode(runs)});
    expect(await update(env.ctx()), 0);
    expect(bin.readAsStringSync(), 'old');
    expect(env.sink.toString(), contains('amm $appVersion is up to date.'));
  });

  test('update keeps amm when the download does not run', () async {
    release('v99.0.0', {ammAsset()!: utf8.encode('not a program')});
    expect(await update(env.ctx()), 1);
    expect(bin.readAsStringSync(), 'old');
    expect(env.sink.toString(), contains("✗ Couldn't update amm"));
    expect(leftovers(bin.parent.path), isEmpty);
  });

  test('update skips amm when not run from an amm binary', () async {
    ammExecutable = () => '${env.tmp.path}/bin/dart';
    release('v99.0.0', {});
    expect(await update(env.ctx()), 0);
    expect(env.sink.toString(), contains('skipping it'));
  });

  test('update says so when GitHub is unreachable', () async {
    httpClient = MockClient((_) async => http.Response('', 500));
    expect(await update(env.ctx()), 1);
    expect(env.sink.toString(), contains("✗ Couldn't check for updates"));
  });

  void plist(String app, String bundleId, String version) =>
      File('$app/Contents/Info.plist')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
          '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
          '<plist version="1.0"><dict>'
          '<key>CFBundleIdentifier</key><string>$bundleId</string>'
          '<key>CFBundleShortVersionString</key><string>$version</string>'
          '</dict></plist>\n',
        );

  String version(String app) => Process.runSync('plutil', [
    '-extract',
    'CFBundleShortVersionString',
    'raw',
    '$app/Contents/Info.plist',
  ]).stdout.toString().trim();

  test(
    'update swaps a GUI app in place, keeping its name, and skips others',
    () async {
      final apps = '${env.tmp.path}/Apps';
      final mine = '$apps/My GUI.app', other = '$apps/Other.app';
      plist(mine, id, '1.0.0');
      File('$mine/Contents/MacOS/old').createSync(recursive: true);
      plist(other, 'com.other', '1.0.0');
      final src = '${env.tmp.path}/src/adofai_mod_installer.app';
      plist(src, id, '99.0.0');
      File('$src/Contents/MacOS/new').createSync(recursive: true);
      final zip = '${env.tmp.path}/gui.zip';
      Process.runSync('ditto', ['-c', '-k', '--keepParent', src, zip]);
      release('v99.0.0', {
        ammAsset()!: utf8.encode(runs),
        'ADOFAIModInstaller-macos.zip': File(zip).readAsBytesSync(),
      });

      expect(await update(env.ctx()), 0);
      expect(version(mine), '99.0.0');
      expect(File('$mine/Contents/MacOS/new').existsSync(), isTrue);
      expect(File('$mine/Contents/MacOS/old').existsSync(), isFalse);
      expect(version(other), '1.0.0');
      expect(leftovers(apps), isEmpty);
      expect(env.sink.toString(), contains('GUI 1.0.0 → 99.0.0 ($mine)'));
    },
    skip: notMac,
  );

  test('update leaves a current GUI alone', () async {
    final mine = '${env.tmp.path}/Apps/X.app';
    plist(mine, id, '99.0.0');
    release('v99.0.0', {ammAsset()!: utf8.encode(runs)});
    expect(await update(env.ctx()), 0);
    expect(env.sink.toString(), contains('GUI 99.0.0 is up to date ($mine).'));
  }, skip: notMac);

  test('update keeps the GUI when the download has no app', () async {
    final apps = '${env.tmp.path}/Apps';
    final mine = '$apps/X.app';
    plist(mine, id, '1.0.0');
    release('v99.0.0', {
      ammAsset()!: utf8.encode(runs),
      'ADOFAIModInstaller-macos.zip': utf8.encode('not a zip'),
    });
    expect(await update(env.ctx()), 1);
    expect(version(mine), '1.0.0');
    expect(leftovers(apps), isEmpty);
    expect(env.sink.toString(), contains("✗ Couldn't update the GUI"));
  }, skip: notMac);
}
