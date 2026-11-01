import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

List<int> zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) => archive.addFile(ArchiveFile.string(name, content)));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  late Directory root;
  late String game, mods;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mod_downloader_test');
    game = p.join(root.path, 'game');
    mods = p.join(game, 'UMMMods');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void install(List<int> bytes) =>
      ModDownloader.installBytes(bytes, modId: 'Test', gameRoot: game, modsDir: mods);

  test('game-root layout merges into the game folder', () {
    install(zip({'Mods/Test.dll': 'a', 'UserLibs/Lib.dll': 'b'}));
    expect(File(p.join(game, 'Mods', 'Test.dll')).existsSync(), isTrue);
    expect(File(p.join(game, 'UserLibs', 'Lib.dll')).existsSync(), isTrue);
    expect(Directory(p.join(mods, 'Test')).existsSync(), isFalse);
  });

  test('single folder goes whole into the mods folder', () {
    install(zip({'Folder/Info.json': '{}', 'Folder/Mod.dll': 'a'}));
    expect(File(p.join(mods, 'Folder', 'Mod.dll')).existsSync(), isTrue);
  });

  test('loose files are wrapped in a folder named after the mod', () {
    install(zip({'Info.json': '{}', 'Mod.dll': 'a'}));
    expect(File(p.join(mods, 'Test', 'Mod.dll')).existsSync(), isTrue);
  });

  for (final name in ['../escaped.txt', 'a/../../escaped.txt']) {
    test('rejects $name', () {
      expect(() => install(zip({name: 'x'})), throwsA(isA<ModDownloadException>()));
      expect(File(p.join(Directory.systemTemp.path, 'escaped.txt')).existsSync(), isFalse);
    });
  }
}
