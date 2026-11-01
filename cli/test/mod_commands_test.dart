import 'dart:convert';
import 'dart:io';

import 'package:amm/src/config.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/mod_commands.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestEnv env;
  late String game;
  setUp(() {
    env = testEnv();
    game = env.game.path;
  });

  GameFacts facts({String os = 'macos', bool found = true, String? path}) =>
      env.facts(
        os: os,
        found: found,
        gamePath: path,
        loader: LoaderKind.melonLoader,
      );

  Ctx ctx(GameFacts f, {Catalog? catalog}) =>
      env.ctx(facts: f, catalog: catalog, yes: false);

  test('list without a game exits 1', () async {
    expect(await list(ctx(facts(found: false, path: '/nope'))), 1);
    expect(
      env.sink.toString(),
      contains('ADOFAI not found (looked in /nope).'),
    );
  });

  test('list shows recorded version and source', () async {
    Directory('$game/Mods/Alpha').createSync(recursive: true);
    File(
      '$game/Mods/Alpha/Info.json',
    ).writeAsStringSync(jsonEncode({'DisplayName': 'Alpha', 'Version': '9'}));
    Directory('$game/Mods/Beta').createSync(recursive: true);
    File(
      '$game/Mods/Beta/Info.json',
    ).writeAsStringSync(jsonEncode({'DisplayName': 'Beta', 'Version': '2.0'}));
    File('$game/UMMMods/Gamma.dll')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    File('$game/.adofai-archive/k/_archive.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({'name': 'K', 'origin': '/o', 'payload': 'p'}),
      );
    (AmmRecord()
          ..mods['alpha'] = const RecordEntry(
            source: 'mods.json',
            version: '1.2',
            paths: ['Mods/Alpha'],
          ))
        .save(game);
    expect(await list(ctx(facts())), 0);
    final lines = env.sink.toString().split('\n');
    expect(lines[0], 'Alpha      1.2  Mods     mods.json');
    expect(lines[1], 'Beta       2.0  Mods     -');
    expect(lines[2], 'Gamma.dll  -    UMMMods  -');
    expect(lines[3], '1 archived (restore them in the GUI)');
  });

  Catalog cat() => Catalog.merge(
    [
      const Mod(id: 'Good', slug: 'good', url: 'u'),
      const Mod(id: 'Bad', slug: 'bad', url: 'u', jalib: true),
      const Mod(id: 'OnlyV2', slug: 'onlyv2', url: 'u', v3: false),
    ],
    [
      const ModlistMod(
        slug: 'good',
        name: 'Good',
        summary: 'nice',
        version: '1.0',
        loaders: {'melonloader'},
      ),
    ],
    ['modlist.org unreachable: x'],
  );

  test('search marks JALib mods broken', () async {
    expect(await search(ctx(facts(), catalog: cat()), 'ba'), 0);
    expect(env.sink.toString(), contains('[broken: needs JALib]'));
  });

  test(
    'search prints warnings, loaders, and hides wrong-version mods',
    () async {
      expect(await search(ctx(facts(), catalog: cat()), ''), 0);
      final s = env.sink.toString();
      expect(s, contains('modlist.org unreachable: x'));
      expect(s, contains('good  1.0  mods.json  ml  Good — nice'));
      expect(s, isNot(contains('onlyv2')));
    },
  );

  test('search with no match', () async {
    expect(await search(ctx(facts(), catalog: cat()), 'zzz'), 0);
    expect(env.sink.toString(), contains('No mods match "zzz".'));
  });

  test('default prints, saves, validates', () async {
    final c = ctx(facts());
    expect(await setDefault(c, null), 0);
    expect(env.sink.toString(), 'default: ml\n');
    expect(await setDefault(c, 'rosetta'), 0);
    expect(Config.load(env: env.configEnv).defaultMethod, Method.rosetta);
    expect(await setDefault(c, 'bogus'), 2);
  });

  test('default refuses native on linux', () async {
    expect(await setDefault(ctx(facts(os: 'linux')), 'native'), 1);
    expect(Config.load(env: env.configEnv).defaultMethod, Method.ml);
  });
}
