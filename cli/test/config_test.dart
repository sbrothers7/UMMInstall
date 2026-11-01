import 'dart:io';

import 'package:amm/src/config.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Map<String, String> env;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('amm_cfg');
    env = {'XDG_CONFIG_HOME': tmp.path};
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('default is ml when file missing', () {
    expect(Config.load(env: env).defaultMethod, Method.ml);
  });

  test('save then load round-trips', () {
    Config.load(env: env)
      ..defaultMethod = Method.rosetta
      ..save(env: env);
    expect(Config.load(env: env).defaultMethod, Method.rosetta);
  });

  test('corrupt file means ml', () {
    File(Config.path(env: env))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{nope');
    expect(Config.load(env: env).defaultMethod, Method.ml);
  });

  test('path uses XDG_CONFIG_HOME', () {
    expect(Config.path(env: env), '${tmp.path}/amm/config.json');
  });

  test('path falls back to ~/.config', () {
    expect(Config.path(env: {'HOME': '/h'}), '/h/.config/amm/config.json');
  });
}
