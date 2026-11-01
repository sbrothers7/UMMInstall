import 'dart:io';
import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('amm_rec'));
  tearDown(() => root.deleteSync(recursive: true));

  test('round-trips method and mods', () {
    Directory(p.join(root.path, 'UMMMods', 'Quartz')).createSync(recursive: true);
    final r = AmmRecord()
      ..method = Method.ml
      ..mods['quartz'] = const RecordEntry(
          source: 'mods.json', version: '2.1.1', paths: ['UMMMods/Quartz']);
    r.save(root.path);
    final back = AmmRecord.load(root.path);
    expect(back.method, Method.ml);
    expect(back.mods['quartz']!.version, '2.1.1');
    expect(back.mods['quartz']!.paths, ['UMMMods/Quartz']);
    expect(back.ownerOf('UMMMods/Quartz/a.dll')?.source, 'mods.json');
    expect(back.ownerOf('UMMMods/Other'), isNull);
  });

  test('corrupt file becomes empty and is kept as .bad', () {
    Directory(p.join(root.path, '.amm')).createSync();
    File(p.join(root.path, '.amm', 'installed.json')).writeAsStringSync('{nope');
    final r = AmmRecord.load(root.path);
    expect(r.method, isNull);
    expect(r.mods, isEmpty);
    expect(File(p.join(root.path, '.amm', 'installed.json.bad')).existsSync(), isTrue);
  });

  test('movePaths rewrites Mods/X to UMMMods/X', () {
    final r = AmmRecord()
      ..mods['a'] = const RecordEntry(source: 'mods.json', paths: ['Mods/A', 'Mods/B/x'])
      ..mods['c'] = const RecordEntry(source: 'mods.json', paths: ['Mods/C']);
    r.movePaths('Mods', 'UMMMods', ['A', 'B']);
    expect(r.mods['a']!.paths, ['UMMMods/A', 'UMMMods/B/x']);
    expect(r.mods['c']!.paths, ['Mods/C']);
  });

  test('load drops entries whose files are gone', () {
    Directory(p.join(root.path, 'Mods', 'Here')).createSync(recursive: true);
    (AmmRecord()
          ..mods['here'] = const RecordEntry(
              source: 'mods.json', paths: ['Mods/Here', 'UserData/gone.cfg'])
          ..mods['gone'] = const RecordEntry(source: 'mods.json', paths: ['Mods/Gone'])
          ..mods['outside'] = const RecordEntry(source: 'mods.json', paths: ['..']))
        .save(root.path);
    expect(AmmRecord.load(root.path).mods.keys, ['here']);
  });
}
