import 'dart:io';

import 'package:adofai_mod_installer/src/app_state.dart';
import 'package:amm_core/amm_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Update All tries every update when one fails', () async {
    final game = Directory.systemTemp.createTempSync('gui_state');
    GamePaths.overrideGamePath(game.path);
    final saved = httpClient;
    addTearDown(() {
      httpClient = saved;
      GamePaths.overrideGamePath(null);
      game.deleteSync(recursive: true);
    });
    final asked = <String>[];
    httpClient = MockClient((req) async {
      asked.add(req.url.pathSegments.last);
      return http.Response('boom', 500);
    });
    final cat = Catalog.merge([
      const Mod(id: 'A', slug: 'a', url: 'https://x/a.zip', version: '2'),
      const Mod(id: 'B', slug: 'b', url: 'https://x/b.zip', version: '2'),
    ], []);
    final state = AppState()
      ..catalog = cat
      ..gameVersion = '3.4.0'
      ..scan = UpgradeScan([
        for (final s in ['a', 'b'])
          Upgrade(entry: cat.find(s)!, from: '1', to: '2', oldPaths: const []),
      ], const [], {'a', 'b'});

    await state.updateAll();

    expect(asked, ['a.zip', 'b.zip']);
    expect(state.modError, allOf(contains('a: '), contains('b: ')));
    expect(state.busySlug, isNull);
  });

  test('Browse lists the most downloaded mods first, mods.json-only last', () {
    final state = AppState()
      ..catalog = Catalog.merge([
        const Mod(id: 'Ours', slug: 'ours', url: 'https://x/o.zip'),
      ], [
        const ModlistMod(slug: 'few', name: 'Few', downloads: 5),
        const ModlistMod(slug: 'many', name: 'Many', downloads: 50),
      ]);
    expect([for (final e in state.browseEntries) e.slug], ['many', 'few', 'ours']);
  });

  test('JALib mods are listed under MelonLoader on macOS, bannered elsewhere', () {
    final game = Directory.systemTemp.createTempSync('gui_jalib');
    GamePaths.overrideGamePath(game.path);
    addTearDown(() {
      GamePaths.overrideGamePath(null);
      game.deleteSync(recursive: true);
    });
    final state = AppState()
      ..catalog = Catalog.merge([
        const Mod(id: 'J', slug: 'j', url: 'https://x/j.zip', jalib: true),
      ], []);
    expect(state.browseEntries, isEmpty);
    expect([for (final e in state.unavailableJalib) e.slug], ['j']);

    Directory('${game.path}/MelonLoader').createSync();
    expect([for (final e in (state..platform = 'macos').browseEntries) e.slug], ['j']);
    expect(state.unavailableJalib, isEmpty);

    // The fork UMMBridge JALib needs ships on macOS only.
    expect((state..platform = 'linux').browseEntries, isEmpty);
    expect([for (final e in state.unavailableJalib) e.slug], ['j']);
  });

  test('UMM on an Intel Mac uses the plain patch, not native UMM', () {
    final state = AppState()..gameVersion = '3.4.0';
    expect((state..appleSilicon = false).guiMethod(LoaderType.umm), Method.rosetta);
    expect((state..appleSilicon = true).guiMethod(LoaderType.umm), Method.native);
    expect(state.guiMethod(LoaderType.melonLoader), Method.ml);
  });
}
