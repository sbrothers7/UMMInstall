import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

GameFacts facts({
  String os = 'macos',
  bool found = true,
  int? major = 3,
  bool appleSilicon = true,
  bool hasArm64Slice = true,
  LoaderKind loader = LoaderKind.none,
  String gamePath = '/game',
}) => GameFacts(
  os: os,
  found: found,
  gamePath: gamePath,
  version: major == null ? null : '$major.0.0',
  major: major,
  appleSilicon: appleSilicon,
  hasArm64Slice: hasArm64Slice,
  loader: loader,
);

void main() {
  test('linux refuses native', () {
    final d = resolveInstall(
      facts(os: 'linux'),
      requested: Method.native,
      fallback: Method.ml,
    );
    expect(d, isA<Refuse>());
    expect((d as Refuse).message, contains('--ml'));
  });

  test('linux uses ml', () {
    final d = resolveInstall(facts(os: 'linux'), fallback: Method.ml);
    expect((d as Proceed).method, Method.ml);
  });

  test('other os refuses', () {
    final d = resolveInstall(facts(os: 'windows'), fallback: Method.ml);
    expect((d as Refuse).message, 'amm supports macOS and Linux only.');
  });

  test('v2 forces rosetta over default', () {
    final d = resolveInstall(facts(major: 2), fallback: Method.ml) as Proceed;
    expect(d.method, Method.rosetta);
    expect(d.confirm, isNull);
  });

  test('v2 refuses explicit ml', () {
    final d = resolveInstall(
      facts(major: 2),
      requested: Method.ml,
      fallback: Method.ml,
    );
    expect((d as Refuse).message, contains('untested on game v2'));
  });

  test('intel refuses native on v3', () {
    final d = resolveInstall(
      facts(appleSilicon: false),
      requested: Method.native,
      fallback: Method.ml,
    );
    expect((d as Refuse).message, contains('Apple Silicon'));
  });

  test('stripped slice refuses ml', () {
    final d = resolveInstall(facts(hasArm64Slice: false), fallback: Method.ml);
    expect((d as Refuse).message, contains('steam://validate/977950'));
  });

  test('rosetta on v3 asks to confirm', () {
    final d =
        resolveInstall(facts(), requested: Method.rosetta, fallback: Method.ml)
            as Proceed;
    expect(d.method, Method.rosetta);
    expect(d.confirm, contains('untested on game v3'));
  });

  test('resolveInstall treats unknown version as v3', () {
    final d = resolveInstall(facts(major: null), fallback: Method.ml);
    expect((d as Proceed).method, Method.ml);
    expect(d.confirm, isNull);
  });

  test('inferMethod', () {
    Method m(LoaderKind l, bool v2, bool as, bool slice) => inferMethod(
      loader: l,
      isV2: v2,
      appleSilicon: as,
      hasArm64Slice: slice,
    );
    expect(m(LoaderKind.umm, true, true, true), Method.rosetta);
    expect(m(LoaderKind.umm, false, true, true), Method.native);
    expect(m(LoaderKind.umm, false, true, false), Method.rosetta);
    expect(m(LoaderKind.umm, false, false, true), Method.rosetta);
    expect(m(LoaderKind.melonLoader, false, true, true), Method.ml);
  });

  Method installed(Method? recorded, LoaderKind loader, {bool v2 = false}) =>
      installedMethod(
        recorded: recorded,
        loader: loader,
        isV2: v2,
        appleSilicon: true,
        hasArm64Slice: true,
      );

  test('installedMethod: record says native but MelonLoader is there', () {
    expect(installed(Method.native, LoaderKind.melonLoader), Method.ml);
  });

  test('installedMethod: record says ml but UMM is there', () {
    expect(installed(Method.ml, LoaderKind.umm), Method.native);
    expect(installed(Method.ml, LoaderKind.umm, v2: true), Method.rosetta);
  });

  test('installedMethod: a consistent record wins', () {
    expect(installed(Method.rosetta, LoaderKind.umm), Method.rosetta);
    expect(installed(Method.ml, LoaderKind.melonLoader), Method.ml);
    expect(installed(null, LoaderKind.umm), Method.native);
  });

  test('missingLoaderFiles lists absent ml files', () {
    final dir = Directory.systemTemp.createTempSync('amm_game_state');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/MelonLoader').createSync();
    final missing = missingLoaderFiles(
      facts(loader: LoaderKind.melonLoader, gamePath: dir.path),
    );
    expect(missing, contains('setup_helper.sh'));
    expect(missing, isNot(contains('MelonLoader')));
    expect(missingLoaderFiles(facts(gamePath: dir.path)), isEmpty);
  });
}
