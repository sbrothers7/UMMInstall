import 'dart:convert';
import 'dart:io';

import 'package:amm/src/loader_commands.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

ScriptCall inst(Method m) => InstallScripts.install(m, os: 'macos')!;
ScriptCall uninst(Method m) => InstallScripts.uninstall(m, os: 'macos')!;

void main() {
  late TestEnv env;
  setUp(() => env = testEnv());

  AmmRecord record() => AmmRecord.load(env.game.path);

  test('install with loader present prints status and runs nothing', () async {
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await install(env.ctx(facts: f)), 0);
    expect(env.calls, isEmpty);
    expect(env.httpCalls, 0);
    final s = env.sink.toString();
    expect(s, contains('Loader:         MelonLoader (ml)'));
    expect(s, contains('Version:        3.4.0'));
    expect(s, contains('Launch options: Steam config not found'));
    expect(s, contains('arm64 slice:    present'));
    expect(s, isNot(contains('amm reinstall')));
  });

  test('status shows the loader and mod counts and changes nothing', () async {
    final game = env.game.path;
    Directory('$game/Mods/Alpha').createSync(recursive: true);
    File('$game/UMMMods/Beta.dll')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    File('$game/.adofai-archive/k/_archive.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'name': 'K', 'origin': '/o', 'payload': 'p'}),
      );
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await status(env.ctx(facts: f)), 0);
    expect(env.calls, isEmpty);
    expect(env.httpCalls, 0);
    final s = env.sink.toString();
    expect(s, contains('Game:           $game'));
    expect(s, contains('Loader:         MelonLoader (ml)'));
    expect(s, contains('Mods:           2 installed, 1 archived'));
  });

  test('status without a loader says none', () async {
    expect(await status(env.ctx()), 0);
    final s = env.sink.toString();
    expect(s, matches(RegExp(r'Loader: +none\n')));
    expect(s, matches(RegExp(r'Mods: +0 installed\n')));
  });

  test('status without a game exits 1', () async {
    final f = env.facts(found: false, gamePath: '/nope');
    expect(await status(env.ctx(facts: f)), 1);
    expect(
      env.sink.toString(),
      contains('ADOFAI not found (looked in /nope).'),
    );
  });

  test('install --native with a different loader suggests reinstall', () async {
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await install(env.ctx(facts: f), method: Method.native), 0);
    expect(
      env.sink.toString(),
      contains('To switch, run: amm reinstall --native'),
    );
  });

  test('install without a game exits 1', () async {
    final f = env.facts(found: false, gamePath: '/nope');
    expect(await install(env.ctx(facts: f)), 1);
    expect(
      env.sink.toString(),
      contains('ADOFAI not found (looked in /nope).'),
    );
  });

  test('install --rosetta on v3 needs confirmation', () async {
    expect(await install(env.ctx(yes: false), method: Method.rosetta), 1);
    expect(env.calls, isEmpty);
  });

  test('install uses saved default', () async {
    final c = env.ctx();
    c.config.defaultMethod = Method.native;
    expect(await install(c), 0);
    expect(env.calls, [inst(Method.native)]);
    expect(record().method, Method.native);
  });

  test('install ml offers to move UMM mods and updates record paths', () async {
    File('${env.game.path}/Mods/A/Info.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'DisplayName': 'A'}));
    (AmmRecord()
          ..mods['a'] = const RecordEntry(
            source: 'mods.json',
            version: '1',
            paths: ['Mods/A'],
          ))
        .save(env.game.path);
    expect(await install(env.ctx(), method: Method.ml), 0);
    expect(env.calls, [inst(Method.ml)]);
    expect(File('${env.game.path}/UMMMods/A/Info.json').existsSync(), isTrue);
    expect(Directory('${env.game.path}/Mods/A').existsSync(), isFalse);
    expect(record().mods['a']!.paths, ['UMMMods/A']);
    expect(record().method, Method.ml);
    expect(
      env.sink.toString(),
      contains('"${env.game.path}/setup_helper.sh" %command%'),
    );
  });

  test(
    'install umm moves UMMMods back to Mods and rewrites record paths',
    () async {
      File('${env.game.path}/UMMMods/A/Info.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${env.game.path}/Mods/X.dll')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      (AmmRecord()
            ..mods['a'] = const RecordEntry(
              source: 'mods.json',
              paths: ['UMMMods/A'],
            ))
          .save(env.game.path);
      expect(await install(env.ctx(), method: Method.native), 0);
      expect(env.calls, [inst(Method.native)]);
      expect(Directory('${env.game.path}/Mods/A').existsSync(), isTrue);
      expect(Directory('${env.game.path}/UMMMods/A').existsSync(), isFalse);
      expect(record().mods['a']!.paths, ['Mods/A']);
      expect(
        env.sink.toString(),
        contains("MelonLoader mods in Mods/ won't load under UMM."),
      );
    },
  );

  test('install says what it will change', () async {
    expect(await install(env.ctx(), method: Method.ml), 0);
    expect(
      env.sink.toString(),
      contains('Installing MelonLoader (ml) into ${env.game.path}…'),
    );
  });

  test('install ml sets Steam launch options when a config exists', () async {
    final cfg = File('${env.tmp.path}/steam/userdata/1/config/localconfig.vdf')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '"UserLocalConfigStore" { "Software" { "Valve" '
        '{ "Steam" { "apps" { "977950" { } } } } } }',
      );
    expect(await install(env.ctx(), method: Method.ml), 0);
    expect(env.sink.toString(), contains('Steam launch options set.'));
    expect(cfg.readAsStringSync(), contains('setup_helper.sh'));
  });

  test(
    'install ml closes a running Steam around the edit and reopens it',
    () async {
      final cfg =
          File('${env.tmp.path}/steam/userdata/1/config/localconfig.vdf')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '"UserLocalConfigStore" { "Software" { "Valve" '
              '{ "Steam" { "apps" { "977950" { } } } } } }',
            );
      SteamConfig.overrideRunning(true);
      expect(await install(env.ctx(), method: Method.ml), 0);
      expect(env.sink.toString(), contains('Reopened Steam.'));
      expect(SteamConfig.isSteamRunning(), isTrue);
      expect(cfg.readAsStringSync(), contains('setup_helper.sh'));
    },
  );

  test('install ml leaves the config alone when Steam may not close', () async {
    final cfg = File('${env.tmp.path}/steam/userdata/1/config/localconfig.vdf')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '"UserLocalConfigStore" { "Software" { "Valve" '
        '{ "Steam" { "apps" { "977950" { } } } } } }',
      );
    SteamConfig.overrideRunning(true);
    expect(await install(env.ctx(yes: false), method: Method.ml), 0);
    expect(env.sink.toString(), contains('set them manually'));
    expect(cfg.readAsStringSync(), isNot(contains('setup_helper.sh')));
  });

  test('failed script exits 1 and records nothing', () async {
    env.scriptExit = 1;
    expect(await install(env.ctx(), method: Method.ml), 1);
    expect(env.sink.toString(), contains('Install failed.'));
    expect(File('${env.game.path}/.amm/installed.json').existsSync(), isFalse);
  });

  test('reinstall switching umm to ml runs uninstall then install', () async {
    final f = env.facts(loader: LoaderKind.umm);
    expect(await reinstall(env.ctx(facts: f), method: Method.ml), 0);
    expect(env.calls, [uninst(Method.native), inst(Method.ml)]);
    expect(record().method, Method.ml);
  });

  test('reinstall same method confirms, uninstalls and installs', () async {
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await reinstall(env.ctx(facts: f)), 0);
    expect(env.calls, [uninst(Method.ml), inst(Method.ml)]);
  });

  test('reinstall without confirmation changes nothing', () async {
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await reinstall(env.ctx(facts: f, yes: false)), 1);
    expect(env.calls, isEmpty);
  });

  test('reinstall without a loader installs', () async {
    expect(await reinstall(env.ctx(), method: Method.ml), 0);
    expect(env.sink.toString(), contains('No loader installed; installing.'));
    expect(env.calls, [inst(Method.ml)]);
  });

  test('reinstall refused target changes nothing', () async {
    final f = env.facts(loader: LoaderKind.umm, major: 2);
    expect(await reinstall(env.ctx(facts: f), method: Method.ml), 1);
    expect(env.calls, isEmpty);
  });

  test(
    'reinstall rosetta to ml with stripped slice stops after uninstall',
    () async {
      final f = env.facts(loader: LoaderKind.umm, hasArm64Slice: false);
      expect(await reinstall(env.ctx(facts: f), method: Method.ml), 0);
      expect(env.calls, [uninst(Method.rosetta)]);
      final s = env.sink.toString();
      expect(s, contains('steam://validate/977950'));
      expect(s, contains('Then run: amm install --ml'));
    },
  );

  GameFacts linuxUmm() =>
      env.facts(os: 'linux', loader: LoaderKind.umm, appleSilicon: false);

  test('linux status shows UMM without a method', () async {
    expect(await install(env.ctx(facts: linuxUmm())), 0);
    expect(env.sink.toString(), contains('Loader:  Unity Mod Manager\n'));
  });

  test(
    'linux reinstall --ml over UMM uninstalls UMM, then installs ml',
    () async {
      expect(await reinstall(env.ctx(facts: linuxUmm()), method: Method.ml), 0);
      expect(env.calls, [
        InstallScripts.uninstall(
          Method.rosetta,
          os: 'linux',
          gamePath: env.game.path,
        ),
        InstallScripts.install(Method.ml, os: 'linux', gamePath: env.game.path),
      ]);
      expect(record().method, Method.ml);
    },
  );

  test('linux uninstall with UMM runs the UMM uninstall script', () async {
    expect(await uninstall(env.ctx(facts: linuxUmm())), 0);
    expect(env.calls, [
      InstallScripts.uninstall(
        Method.rosetta,
        os: 'linux',
        gamePath: env.game.path,
      ),
    ]);
  });

  test('uninstall without loader exits 0', () async {
    expect(await uninstall(env.ctx()), 0);
    expect(env.sink.toString(), contains('No mod loader installed.'));
    expect(env.calls, isEmpty);
  });

  test('uninstall clears record method', () async {
    (AmmRecord()..method = Method.ml).save(env.game.path);
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await uninstall(env.ctx(facts: f)), 0);
    expect(env.calls, [uninst(Method.ml)]);
    expect(record().method, isNull);
  });

  test('uninstall without -y on a non-terminal refuses', () async {
    final f = env.facts(loader: LoaderKind.melonLoader);
    expect(await uninstall(env.ctx(facts: f, yes: false)), 1);
    expect(env.calls, isEmpty);
  });
}
