import 'dart:io';
import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory game;
  setUp(() {
    game = Directory.systemTemp.createTempSync('amm_store');
    GamePaths.overrideGamePath(game.path);
  });
  tearDown(() {
    GamePaths.overrideGamePath(null);
    game.deleteSync(recursive: true);
  });

  void file(String rel) => File(p.join(game.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync('x');

  test('findUmmMods finds folders with Info.json only', () {
    file('Mods/A/Info.json');
    file('Mods/B/x.dll');
    file('Mods/c.dll');
    expect(ModStore.findUmmMods(GamePaths.ummModsPath), ['A']);
  });

  test('moveMods moves and reports', () {
    file('Mods/A/info.json');
    final errs = <String>[];
    final moved = ModStore.moveMods(['A', 'Missing'], GamePaths.ummModsPath,
        GamePaths.melonModsPath, onError: (n, _) => errs.add(n));
    expect(moved, ['A']);
    expect(errs, ['Missing']);
    expect(File(p.join(game.path, 'UMMMods/A/info.json')).existsSync(), isTrue);
    expect(Directory(p.join(game.path, 'Mods/A')).existsSync(), isFalse);
  });

  test('archive then restore puts the mod back', () {
    file('UMMMods/A/Info.json');
    final mod = ModStore.scanInstalled().single;
    ModStore.archive(mod);
    expect(ModStore.scanInstalled(), isEmpty);
    final a = ModStore.scanArchived().single;
    ModStore.restore(a);
    expect(ModStore.scanArchived(), isEmpty);
    expect(File(p.join(game.path, 'UMMMods/A/Info.json')).existsSync(), isTrue);
  });
}
