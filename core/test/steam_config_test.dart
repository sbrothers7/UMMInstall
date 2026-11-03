import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

void main() {
  test('readLaunchOptions unescapes the value for 977950', () {
    const vdf = r'"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "977950" { "LaunchOptions" "\"/g/setup_helper.sh\" %command%" } } } } } }';
    expect(SteamConfig.readLaunchOptions(vdf), '"/g/setup_helper.sh" %command%');
  });

  test('readLaunchOptions is null without the app block', () {
    const vdf = r'"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "1" { "LaunchOptions" "x" } } } } } }';
    expect(SteamConfig.readLaunchOptions(vdf), isNull);
  });

  // localconfig.vdf also keeps cloud-sync state in a top-level "apps" block,
  // which Steam may write before Software. Launch options live only under
  // Software/Valve/Steam/apps.
  const cloudFirst = '"UserLocalConfigStore" { "apps" { "977950" { "cloud" { "x" "1" } } } '
      '"Software" { "Valve" { "Steam" { "apps" { "977950" { "LastPlayed" "1" } } } } } }';

  test('setLaunchOptions writes under Software/Valve/Steam/apps, not the cloud block', () {
    final tmp = Directory.systemTemp.createTempSync('amm_steam');
    addTearDown(() {
      SteamConfig.overrideRoots(null);
      tmp.deleteSync(recursive: true);
    });
    final cfg = File('${tmp.path}/userdata/1/config/localconfig.vdf')
      ..createSync(recursive: true)
      ..writeAsStringSync(cloudFirst);
    SteamConfig.overrideRoots([tmp.path]);

    expect(SteamConfig.setLaunchOptions('/g/setup_helper.sh').updated, 1);
    final text = cfg.readAsStringSync();
    expect(SteamConfig.readLaunchOptions(text), '"/g/setup_helper.sh" %command%');
    expect(text.indexOf('LaunchOptions'), greaterThan(text.indexOf('"Software"')));

    expect(SteamConfig.clearLaunchOptions().updated, 1);
    expect(SteamConfig.readLaunchOptions(cfg.readAsStringSync()), '');
  });

  test('setLaunchOptions reports noConfig when no config has the Steam apps block', () {
    final tmp = Directory.systemTemp.createTempSync('amm_steam');
    addTearDown(() {
      SteamConfig.overrideRoots(null);
      tmp.deleteSync(recursive: true);
    });
    File('${tmp.path}/userdata/1/config/localconfig.vdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('"UserLocalConfigStore" { "apps" { } }');
    SteamConfig.overrideRoots([tmp.path]);
    expect(SteamConfig.setLaunchOptions('/g/setup_helper.sh').noConfig, isTrue);
  });

  test('overrideRoots replaces the Steam roots', () {
    final tmp = Directory.systemTemp.createTempSync('amm_steam');
    addTearDown(() {
      SteamConfig.overrideRoots(null);
      tmp.deleteSync(recursive: true);
    });
    final cfg = File('${tmp.path}/userdata/1/config/localconfig.vdf')
      ..createSync(recursive: true);
    SteamConfig.overrideRoots([tmp.path]);
    expect(SteamConfig.localConfigPaths(), [cfg.path]);
    SteamConfig.overrideRoots(null);
    expect(SteamConfig.localConfigPaths(), isNot(contains(cfg.path)));
  });
}
