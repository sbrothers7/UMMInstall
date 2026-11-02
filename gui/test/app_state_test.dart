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
}
