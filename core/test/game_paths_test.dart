import 'dart:convert';
import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

List<int> header(String v) => [0, 0, 0, 0x16, ...latin1.encode(v), 0];

void main() {
  test('unity 6 maps to game v3', () {
    expect(GamePaths.unityMajorToGameMajor(header('6000.0.58f2')), 3);
  });
  test('unity 2022 maps to game v2', () {
    expect(GamePaths.unityMajorToGameMajor(header('2022.3.62f1')), 2);
  });
  test('no version gives null', () {
    expect(
      GamePaths.unityMajorToGameMajor(latin1.encode('no version here')),
      isNull,
    );
  });

  test('findDataDir prefers the folder holding globalgamemanagers', () {
    final tmp = Directory.systemTemp.createTempSync('amm_game');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // A stray Proton-named folder beside the native build's.
    Directory('${tmp.path}/A Dance of Fire and Ice_Data/Managed')
        .createSync(recursive: true);
    File('${tmp.path}/ADanceOfFireAndIce_Data/globalgamemanagers')
        .createSync(recursive: true);
    expect(GamePaths.findDataDir(tmp.path),
        '${tmp.path}/ADanceOfFireAndIce_Data');
  });
  test('findDataDir finds the Proton build and gives null for none', () {
    final tmp = Directory.systemTemp.createTempSync('amm_game');
    addTearDown(() => tmp.deleteSync(recursive: true));
    expect(GamePaths.findDataDir(tmp.path), isNull);
    File('${tmp.path}/A Dance of Fire and Ice_Data/globalgamemanagers')
        .createSync(recursive: true);
    expect(GamePaths.findDataDir(tmp.path),
        '${tmp.path}/A Dance of Fire and Ice_Data');
  });
}
