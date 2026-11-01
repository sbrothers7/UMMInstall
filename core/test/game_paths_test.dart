import 'dart:convert';

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
}
