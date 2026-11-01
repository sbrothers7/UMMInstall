import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

void main() {
  const base = 'https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/';
  ScriptCall c(String path, [List<String> args = const []]) =>
      ScriptCall('$base$path', args);

  test('macos', () {
    expect(InstallScripts.install(Method.ml, os: 'macos'),
        c('macos/adofai-melonloader.sh'));
    expect(InstallScripts.uninstall(Method.ml, os: 'macos'),
        c('macos/adofai-melonloader-uninstall.sh'));
    expect(InstallScripts.install(Method.rosetta, os: 'macos'),
        c('macos/adofai-umm.sh', ['rosetta']));
    expect(InstallScripts.install(Method.native, os: 'macos'),
        c('macos/adofai-umm.sh', ['native']));
    expect(InstallScripts.uninstall(Method.native, os: 'macos'),
        c('macos/adofai-umm-uninstall.sh', ['native']));
    expect(InstallScripts.uninstall(Method.rosetta, os: 'macos'),
        c('macos/adofai-umm-uninstall.sh', ['rosetta']));
  });

  test('linux', () {
    expect(InstallScripts.install(Method.ml, os: 'linux', gamePath: '/g'),
        c('linux/adofai-melonloader.sh', ['/g']));
    expect(InstallScripts.uninstall(Method.ml, os: 'linux', gamePath: '/g'),
        c('linux/adofai-melonloader-uninstall.sh', ['/g']));
    expect(InstallScripts.install(Method.native, os: 'linux'), isNull);
    expect(InstallScripts.uninstall(Method.rosetta, os: 'linux'), isNull);
  });

  test('windows', () {
    expect(InstallScripts.install(Method.ml, os: 'windows'),
        c('windows/adofai-melonloader.ps1'));
    expect(InstallScripts.uninstall(Method.ml, os: 'windows'),
        c('windows/adofai-melonloader-uninstall.ps1'));
    expect(InstallScripts.install(Method.native, os: 'windows'), isNull);
  });

  test('ScriptCall equality', () {
    expect(const ScriptCall('u', ['a']), const ScriptCall('u', ['a']));
    expect(const ScriptCall('u', ['a']).hashCode,
        const ScriptCall('u', ['a']).hashCode);
    expect(const ScriptCall('u', ['a']), isNot(const ScriptCall('u', ['b'])));
    expect(const ScriptCall('u'), isNot(const ScriptCall('u', ['a'])));
  });
}
