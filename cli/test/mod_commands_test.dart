import 'dart:convert';
import 'dart:io';

import 'package:amm/src/config.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/mod_commands.dart';
import 'package:amm_core/amm_core.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('list with no mods says so', () async {
    expect(await list(ctx(facts())), 0);
    expect(env.sink.toString(), 'No mods installed.\n');
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

  // --- modinstall / mr / upgrade ---

  ModlistMod mod(String slug, {List<String> deps = const [], String? v}) =>
      ModlistMod(slug: slug, name: slug, version: v, dependencies: deps);

  /// Serves a one-folder zip named after the requested slug; [offline] fails
  /// as a dropped connection.
  void serveZips({String? offline}) {
    httpClient = MockClient((req) async {
      final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
      if (slug == offline) throw http.ClientException('offline');
      final a = Archive()
        ..addFile(ArchiveFile.string('$slug/Info.json', '{"Id":"$slug"}'))
        ..addFile(ArchiveFile.string('$slug/M.dll', 'a'));
      return http.Response.bytes(ZipEncoder().encodeBytes(a), 200);
    });
  }

  Ctx yesCtx(Catalog c, {GameFacts? f}) =>
      env.ctx(facts: f ?? facts(), catalog: c, yes: true);

  test('mi installs dependencies first and records both', () async {
    serveZips();
    final c = Catalog.merge([], [
      mod('main', deps: ['dep'], v: '1.0'),
      mod('dep', v: '2.0'),
    ]);
    expect(await modinstall(yesCtx(c), ['main']), 0);
    final s = env.sink.toString();
    expect(s, contains('Installing: dep (dependency), main'));
    expect(s, contains('✓ dep 2.0'));
    expect(s, contains('✓ main 1.0'));
    final r = AmmRecord.load(game);
    expect(r.mods.keys, containsAll(['main', 'dep']));
    expect(Directory('$game/UMMMods/dep').existsSync(), isTrue);
    expect(Directory('$game/UMMMods/main').existsSync(), isTrue);
  });

  test('mi with unknown slug installs nothing and exits 1', () async {
    serveZips();
    final c = Catalog.merge([], [mod('main')]);
    expect(await modinstall(yesCtx(c), ['main', 'nope']), 1);
    expect(
      env.sink.toString(),
      contains('Unknown mod(s): nope. Try `amm search`.'),
    );
    expect(Directory('$game/UMMMods/main').existsSync(), isFalse);
  });

  test('mi without loader exits 1', () async {
    final c = Catalog.merge([], [mod('main')]);
    final f = env.facts(); // LoaderKind.none
    expect(await modinstall(yesCtx(c, f: f), ['main']), 1);
    expect(
      env.sink.toString(),
      contains('No mod loader installed. Run `amm install` first.'),
    );
  });

  test('mi keeps going after a failed mod and exits 1', () async {
    httpClient = MockClient((req) async => http.Response('boom', 500));
    final c = Catalog.merge([], [mod('main')]);
    expect(await modinstall(yesCtx(c), ['main']), 1);
    expect(env.sink.toString(), contains('✗ main: '));
  });

  test('mi continues after a ClientException on one mod', () async {
    serveZips(offline: 'aa');
    final c = Catalog.merge([], [mod('aa', v: '1'), mod('bb', v: '1')]);
    expect(await modinstall(yesCtx(c), ['aa', 'bb']), 1);
    final s = env.sink.toString();
    expect(s, contains('✗ aa: Download failed: offline'));
    expect(s, contains('✓ bb 1'));
    expect(Directory('$game/UMMMods/bb').existsSync(), isTrue);
  });

  void seedInstalled(String slug, String version) {
    Directory('$game/UMMMods/$slug').createSync(recursive: true);
    File('$game/UMMMods/$slug/M.dll').writeAsStringSync('old');
    final r = AmmRecord.load(game);
    r.mods[slug] = RecordEntry(
      source: 'modlist.org',
      version: version,
      paths: ['UMMMods/$slug'],
    );
    r.save(game);
  }

  test('mr asks before deleting', () async {
    seedInstalled('a', '1.0');
    final c = env.ctx(facts: facts(), yes: false);
    expect(await remove(c, ['a']), 1);
    expect(env.sink.toString(), contains('Pass -y'));
    expect(File('$game/UMMMods/a/M.dll').existsSync(), isTrue);
  });

  test('mr deletes with -y, reports a miss and exits 1', () async {
    seedInstalled('a', '1.0');
    expect(await remove(yesCtx(Catalog([])), ['a', 'zzz']), 1);
    final s = env.sink.toString();
    expect(s, contains('✗ No installed mod matches "zzz".'));
    expect(Directory('$game/UMMMods/a').existsSync(), isFalse);
    expect(AmmRecord.load(game).mods, isEmpty);
  });

  test('mr --keep archives', () async {
    seedInstalled('a', '1.0');
    expect(await remove(yesCtx(Catalog([])), ['a'], keep: true), 0);
    expect(Directory('$game/UMMMods/a').existsSync(), isFalse);
    expect(ModStore.scanArchived(), hasLength(1));
  });

  test('upgrade with one slug only touches that mod', () async {
    serveZips();
    seedInstalled('a', '1.0');
    seedInstalled('b', '1.0');
    final c = Catalog.merge([], [mod('a', v: '2.0'), mod('b', v: '2.0')]);
    expect(await upgrade(yesCtx(c), ['A']), 0);
    expect(env.sink.toString(), contains('Upgrading: a 1.0 → 2.0'));
    final r = AmmRecord.load(game);
    expect(r.mods['a']!.version, '2.0');
    expect(r.mods['b']!.version, '1.0');
  });

  test('upgrade of a mod that is not installed says so', () async {
    final c = Catalog.merge([], [mod('a', v: '1.0')]);
    expect(await upgrade(yesCtx(c), ['a']), 0);
    expect(
      env.sink.toString(),
      contains("a is not installed (or amm can't tell where it came from)."),
    );
  });

  test('upgrade reports up to date', () async {
    seedInstalled('a', '1.0');
    final c = Catalog.merge([], [mod('a', v: '1.0')]);
    expect(await upgrade(yesCtx(c), ['a']), 0);
    expect(env.sink.toString(), contains('a is up to date.'));
    env.sink.clear();
    expect(await upgrade(yesCtx(c), []), 0);
    expect(env.sink.toString(), contains('All mods are up to date.'));
  });
}
