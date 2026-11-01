import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  late Directory root;
  late String game, mods;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mod_downloader_test');
    game = p.join(root.path, 'game');
    mods = p.join(game, 'UMMMods');
  });
  tearDown(() => root.deleteSync(recursive: true));

  List<String> install(List<int> bytes, {bool melonNative = false, String? modsDir}) =>
      ModDownloader.installBytes(bytes,
          modId: 'Test', gameRoot: game, modsDir: modsDir ?? mods, melonNative: melonNative);

  test('game-root layout merges into the game folder', () {
    final placed = install(zip({'Mods/Test.dll': 'a', 'UserLibs/Lib.dll': 'b'}));
    expect(placed, unorderedEquals([p.join(game, 'Mods', 'Test.dll'), p.join(game, 'UserLibs', 'Lib.dll')]));
    expect(File(p.join(game, 'Mods', 'Test.dll')).existsSync(), isTrue);
    expect(File(p.join(game, 'UserLibs', 'Lib.dll')).existsSync(), isTrue);
    expect(Directory(p.join(mods, 'Test')).existsSync(), isFalse);
  });

  test('single folder goes whole into the mods folder', () {
    final placed = install(zip({'Folder/Info.json': '{}', 'Folder/Mod.dll': 'a'}));
    expect(placed, [p.join(mods, 'Folder')]);
    expect(File(p.join(mods, 'Folder', 'Mod.dll')).existsSync(), isTrue);
  });

  test('loose files are wrapped in a folder named after the mod', () {
    final placed = install(zip({'Info.json': '{}', 'Mod.dll': 'a'}));
    expect(placed, [p.join(mods, 'Test')]);
    expect(File(p.join(mods, 'Test', 'Mod.dll')).existsSync(), isTrue);
  });

  test('melonNative puts loose dlls straight into Mods', () {
    final dir = p.join(game, 'Mods');
    final placed = install(zip({'X.dll': 'a'}), melonNative: true, modsDir: dir);
    expect(File(p.join(dir, 'X.dll')).existsSync(), isTrue);
    expect(placed, [p.join(dir, 'X.dll')]);
  });

  test('download surfaces modlist statusMessage', () {
    final saved = httpClient;
    addTearDown(() => httpClient = saved);
    httpClient = MockClient((_) async => http.Response(
        '{"statusMessage":"Requested version has no umm macos download link."}', 404));
    expect(
        ModDownloader.download('https://x/y'),
        throwsA(predicate((e) =>
            e is ModDownloadException &&
            e.message.contains('HTTP 404') &&
            e.message.contains('no umm macos download link'))));
  });

  for (final name in ['../escaped.txt', 'a/../../escaped.txt']) {
    test('rejects $name', () {
      expect(() => install(zip({name: 'x'})), throwsA(isA<ModDownloadException>()));
      expect(File(p.join(Directory.systemTemp.path, 'escaped.txt')).existsSync(), isFalse);
    });
  }
}
