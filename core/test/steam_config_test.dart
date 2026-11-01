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
}
