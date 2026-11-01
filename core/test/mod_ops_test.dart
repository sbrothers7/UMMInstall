import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

ModlistMod theirs(String slug,
        {List<String> deps = const [], String? version, List<String> loaders = const []}) =>
    ModlistMod(
        slug: slug,
        name: slug,
        version: version,
        dependencies: deps,
        loaders: loaders.toSet());

void main() {
  late http.Client saved;
  late Directory root;
  late String game;
  final requested = <Uri>[];

  setUp(() {
    saved = httpClient;
    requested.clear();
    root = Directory.systemTemp.createTempSync('mod_ops_test');
    game = p.join(root.path, 'game');
    Directory(game).createSync();
    GamePaths.overrideGamePath(game);
    httpClient = MockClient((req) async {
      requested.add(req.url);
      if (req.url.path.contains('fail')) return http.Response('boom', 500);
      return http.Response.bytes(
          zip({'Folder/Info.json': '{"Id":"Folder"}', 'Folder/M.dll': 'a'}), 200);
    });
  });
  tearDown(() {
    httpClient = saved;
    root.deleteSync(recursive: true);
  });

  ModTarget target({bool isV2 = false, bool melon = false}) => ModTarget(
      gameRoot: game, isV2: isV2, gameVersion: '3.4.0', melon: melon, platform: 'macos');

  final catalog = Catalog.merge([
    const Mod(id: 'Ours', slug: 'ours', url: 'https://x/ours.zip', version: 'v1.0'),
    const Mod(id: 'J', slug: 'j', url: 'https://x/j.zip', jalib: true),
    const Mod(id: 'Old', slug: 'old', url: 'https://x/old.zip', v2: false),
    const Mod(id: 'Fail', slug: 'fail', url: 'https://x/fail.zip', version: '2'),
  ], [
    theirs('overlayer'),
    theirs('overlayer-module-adofai', deps: ['overlayer']),
    theirs('mlonly', loaders: ['melonloader'], version: '1'),
    theirs('both', loaders: ['umm'], version: '1'),
    theirs('orphan', deps: ['ghost']),
  ]);

  group('plan', () {
    test('orders dependencies first', () {
      final pl = ModOps.plan(catalog, ['overlayer-module-adofai'], AmmRecord());
      expect(pl.order.map((e) => e.slug), ['overlayer', 'overlayer-module-adofai']);
      expect(pl.missing, isEmpty);
    });

    test('skips recorded dependencies', () {
      final r = AmmRecord()
        ..mods['overlayer'] = const RecordEntry(source: 'modlist.org', paths: ['UMMMods/o']);
      final pl = ModOps.plan(catalog, ['overlayer-module-adofai', 'overlayer'], r);
      expect(pl.order.map((e) => e.slug), ['overlayer', 'overlayer-module-adofai']);
      final pl2 = ModOps.plan(catalog, ['overlayer-module-adofai'], r);
      expect(pl2.order.map((e) => e.slug), ['overlayer-module-adofai']);
    });

    test('reports unknown slugs', () {
      final pl = ModOps.plan(catalog, ['nope', 'orphan'], AmmRecord());
      expect(pl.missing, unorderedEquals(['nope', 'ghost']));
      expect(pl.order.map((e) => e.slug), ['orphan']);
    });
  });

  group('install', () {
    test('records relative paths and version', () async {
      final e = await ModOps.install(catalog.find('ours')!, target());
      expect(e.source, 'mods.json');
      expect(e.version, 'v1.0');
      expect(e.paths, ['Mods/Folder']);
      expect(File(p.join(game, 'Mods', 'Folder', 'M.dll')).existsSync(), isTrue);
    });

    test('refuses jalib', () {
      expect(ModOps.install(catalog.find('j')!, target()),
          throwsA(predicate((e) => e.toString().contains('depends on JALib'))));
    });

    test('refuses a v2:false mod on v2', () {
      expect(ModOps.install(catalog.find('old')!, target(isV2: true)),
          throwsA(predicate((e) => e.toString() == "old isn't available for game v2.")));
    });

    test('ml-only modlist mod refused on UMM', () {
      expect(
          ModOps.install(catalog.find('mlonly')!, target()),
          throwsA(predicate((e) =>
              e.toString() == 'mlonly needs MelonLoader. Switch with `amm reinstall --ml`.')));
    });

    test('ml install of ml-native mod requests melonloader and lands in Mods', () async {
      final e = await ModOps.install(catalog.find('mlonly')!, target(melon: true));
      expect(requested.single.queryParameters['loader'], 'melonloader');
      expect(e.source, 'modlist.org');
      expect(e.version, '1');
      expect(File(p.join(game, 'Mods', 'Folder', 'M.dll')).existsSync(), isTrue);
    });

    test('ml install of umm-capable mod goes to UMMMods', () async {
      await ModOps.install(catalog.find('both')!, target(melon: true));
      expect(requested.single.queryParameters['loader'], 'umm');
      expect(Directory(p.join(game, 'UMMMods', 'Folder')).existsSync(), isTrue);
    });
  });

  group('remove', () {
    void mod(String rel) {
      Directory(p.join(game, rel)).createSync(recursive: true);
      File(p.join(game, rel, 'M.dll')).writeAsStringSync('a');
    }

    test('deletes recorded paths and drops the entry', () {
      mod('Mods/Folder');
      final r = AmmRecord()
        ..mods['ours'] = const RecordEntry(source: 'mods.json', paths: ['Mods/Folder']);
      expect(ModOps.remove('ours', r, game), ['Mods/Folder']);
      expect(Directory(p.join(game, 'Mods', 'Folder')).existsSync(), isFalse);
      expect(r.mods, isEmpty);
    });

    test('--keep archives', () {
      mod('Mods/Folder');
      final r = AmmRecord()
        ..mods['ours'] = const RecordEntry(source: 'mods.json', paths: ['Mods/Folder']);
      ModOps.remove('ours', r, game, keep: true);
      expect(Directory(p.join(game, 'Mods', 'Folder')).existsSync(), isFalse);
      expect(ModStore.scanArchived().map((a) => a.name), isNotEmpty);
    });

    test('matches unrecorded folder by name', () {
      mod('Mods/Quartz');
      expect(ModOps.remove('quartz', AmmRecord(), game), ['Mods/Quartz']);
      expect(Directory(p.join(game, 'Mods', 'Quartz')).existsSync(), isFalse);
    });

    test('remove refuses record paths outside the game folder', () {
      final f = File(p.join(root.path, 'outside.txt'))..writeAsStringSync('x');
      final r = AmmRecord()
        ..mods['ours'] = const RecordEntry(source: 'mods.json', paths: ['../outside.txt']);
      expect(() => ModOps.remove('ours', r, game),
          throwsA(isA<ModOpsException>()));
      expect(f.existsSync(), isTrue);
    });

    test('throws when nothing matches', () {
      expect(() => ModOps.remove('zzz', AmmRecord(), game),
          throwsA(predicate((e) => e.toString() == 'No installed mod matches "zzz".')));
    });
  });

  group('upgrades', () {
    test('offers differing version only', () {
      final r = AmmRecord()
        ..mods['ours'] = const RecordEntry(
            source: 'mods.json', version: '1.0', paths: ['Mods/Folder'])
        ..mods['both'] = const RecordEntry(
            source: 'modlist.org', version: '0', paths: ['UMMMods/B'])
        ..mods['mlonly'] = const RecordEntry(
            source: 'modlist.org', version: '1', paths: ['Mods/ML']);
      final s = ModOps.upgrades(catalog, r, [], target());
      expect(s.upgrades.map((u) => u.entry.slug), ['both']);
      expect(s.upgrades.single.from, '0');
      expect(s.upgrades.single.to, '1');
      expect(s.upgrades.single.oldPaths, ['UMMMods/B']);
    });

    test('matches unrecorded folders and lists the rest as unknown', () {
      final a = Directory(p.join(game, 'Mods', 'OursDir'))..createSync(recursive: true);
      File(p.join(a.path, 'Info.json')).writeAsStringSync('{"Id":"ours","Version":"0.5"}');
      final b = Directory(p.join(game, 'Mods', 'Mystery'))..createSync(recursive: true);
      File(p.join(b.path, 'Info.json')).writeAsStringSync('{"Id":"mystery"}');
      final s = ModOps.upgrades(catalog, AmmRecord(), ModStore.scanInstalled(), target());
      expect(s.upgrades.map((u) => u.entry.slug), ['ours']);
      expect(s.unknown, ['Mystery']);
    });

    test('upgrade keeps the old mod when the download fails', () async {
      final old = Directory(p.join(game, 'Mods', 'Old'))..createSync(recursive: true);
      final u = Upgrade(
          entry: catalog.find('fail')!, from: '1', to: '2', oldPaths: ['Mods/Old']);
      await expectLater(ModOps.upgrade(u, target()), throwsA(isA<ModDownloadException>()));
      expect(old.existsSync(), isTrue);
    });

    test('upgrade keeps the old mod when the download is not a zip', () async {
      httpClient = MockClient((_) async => http.Response('<html>nope</html>', 200));
      final old = Directory(p.join(game, 'Mods', 'Old'))..createSync(recursive: true);
      final r = AmmRecord()
        ..mods['ours'] = const RecordEntry(source: 'mods.json', version: '0', paths: ['Mods/Old']);
      final u = Upgrade(
          entry: catalog.find('ours')!, from: '0', to: 'v1.0', oldPaths: ['Mods/Old']);
      await expectLater(ModOps.upgrade(u, target()), throwsA(anything));
      expect(old.existsSync(), isTrue);
      expect(r.mods['ours']!.paths, ['Mods/Old']);
    });

    test('upgrade replaces old paths after download', () async {
      final old = Directory(p.join(game, 'Mods', 'Old'))..createSync(recursive: true);
      final u = Upgrade(
          entry: catalog.find('ours')!, from: '0', to: 'v1.0', oldPaths: ['Mods/Old']);
      final e = await ModOps.upgrade(u, target());
      expect(old.existsSync(), isFalse);
      expect(e.paths, ['Mods/Folder']);
    });
  });
}
