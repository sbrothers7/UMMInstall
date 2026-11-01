import 'dart:convert';
import 'dart:io';

import 'package:amm/src/config.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/mod_commands.dart';
import 'package:amm/src/out.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

GameFacts facts({String os = 'macos', bool found = true, String path = '/x'}) =>
    GameFacts(
      os: os, found: found, gamePath: path, version: '3.4.0', major: 3,
      appleSilicon: true, hasArm64Slice: true, loader: LoaderKind.melonLoader,
    );

void main() {
  late Directory tmp;
  late StringBuffer sink;
  late Map<String, String> env;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('amm_mc');
    sink = StringBuffer();
    env = {'XDG_CONFIG_HOME': '${tmp.path}/cfg'};
    GamePaths.overrideGamePath(tmp.path);
  });
  tearDown(() {
    GamePaths.overrideGamePath(null);
    tmp.deleteSync(recursive: true);
  });

  Ctx ctx(GameFacts f, {Catalog? catalog}) => Ctx(
        out: Out(sink: sink),
        config: Config.load(env: env),
        facts: () async => f,
        catalog: () async => catalog ?? Catalog([]),
      );

  test('list without a game exits 1', () async {
    expect(await list(ctx(facts(found: false, path: '/nope'))), 1);
    expect(sink.toString(), contains('ADOFAI not found (looked in /nope).'));
  });

  test('list shows recorded version and source', () async {
    Directory('${tmp.path}/Mods/Alpha').createSync(recursive: true);
    File('${tmp.path}/Mods/Alpha/Info.json')
        .writeAsStringSync(jsonEncode({'DisplayName': 'Alpha', 'Version': '9'}));
    Directory('${tmp.path}/Mods/Beta').createSync(recursive: true);
    File('${tmp.path}/Mods/Beta/Info.json')
        .writeAsStringSync(jsonEncode({'DisplayName': 'Beta', 'Version': '2.0'}));
    File('${tmp.path}/UMMMods/Gamma.dll')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    File('${tmp.path}/.adofai-archive/k/_archive.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'name': 'K', 'origin': '/o', 'payload': 'p'}));
    (AmmRecord()
          ..mods['alpha'] = const RecordEntry(
              source: 'mods.json', version: '1.2', paths: ['Mods/Alpha']))
        .save(tmp.path);
    expect(await list(ctx(facts(path: tmp.path))), 0);
    final lines = sink.toString().split('\n');
    expect(lines[0], 'Alpha      1.2  Mods     mods.json');
    expect(lines[1], 'Beta       2.0  Mods     -');
    expect(lines[2], 'Gamma.dll  -    UMMMods  -');
    expect(lines[3], '1 archived (restore them in the GUI)');
  });

  Catalog cat() => Catalog.merge([
        const Mod(id: 'Good', slug: 'good', url: 'u'),
        const Mod(id: 'Bad', slug: 'bad', url: 'u', jalib: true),
        const Mod(id: 'OnlyV2', slug: 'onlyv2', url: 'u', v3: false),
      ], [
        const ModlistMod(
            slug: 'good', name: 'Good', summary: 'nice', version: '1.0',
            loaders: {'melonloader'}),
      ], ['modlist.org unreachable: x']);

  test('search marks JALib mods broken', () async {
    expect(await search(ctx(facts(), catalog: cat()), 'ba'), 0);
    expect(sink.toString(), contains('[broken: needs JALib]'));
  });

  test('search prints warnings, loaders, and hides wrong-version mods', () async {
    expect(await search(ctx(facts(), catalog: cat()), ''), 0);
    final s = sink.toString();
    expect(s, contains('modlist.org unreachable: x'));
    expect(s, contains('good  1.0  mods.json  ml  Good — nice'));
    expect(s, isNot(contains('onlyv2')));
  });

  test('search with no match', () async {
    expect(await search(ctx(facts(), catalog: cat()), 'zzz'), 0);
    expect(sink.toString(), contains('No mods match "zzz".'));
  });

  test('default prints, saves, validates', () async {
    final c = ctx(facts());
    expect(await setDefault(c, null), 0);
    expect(sink.toString(), 'default: ml\n');
    expect(await setDefault(c, 'rosetta'), 0);
    expect(Config.load(env: env).defaultMethod, Method.rosetta);
    expect(await setDefault(c, 'bogus'), 2);
  });

  test('default refuses native on linux', () async {
    expect(await setDefault(ctx(facts(os: 'linux')), 'native'), 1);
    expect(Config.load(env: env).defaultMethod, Method.ml);
  });
}
