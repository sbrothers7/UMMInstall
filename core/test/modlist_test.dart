import 'dart:convert';

import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const quartz = {
  'slug': 'quartz',
  'name': 'Quartz',
  'summary': 'A mod.',
  'dependencies': [],
  'latestVersion': {
    'version': '2.1.1',
    'files': [
      {'index': 0, 'loader': 'melonloader', 'platform': null, 'gameVersion': null},
      {'index': 1, 'loader': 'umm', 'platform': null, 'gameVersion': null},
    ],
  },
};

void main() {
  late http.Client saved;
  setUp(() => saved = httpClient);
  tearDown(() => httpClient = saved);

  test('fromJson reads version, deps and loaders', () {
    final m = ModlistMod.fromJson(quartz);
    expect(m.slug, 'quartz');
    expect(m.version, '2.1.1');
    expect(m.dependencies, isEmpty);
    expect(m.loaders, {'melonloader', 'umm'});
  });

  test('fromJson tolerates missing fields', () {
    final m = ModlistMod.fromJson({'slug': 's', 'name': 'S', 'latestVersion': null});
    expect(m.summary, '');
    expect(m.version, isNull);
    expect(m.dependencies, isEmpty);
    expect(m.loaders, isEmpty);
  });

  test('fetchAll follows pagination', () async {
    final pages = <String>[];
    httpClient = MockClient((req) async {
      final page = req.url.queryParameters['page']!;
      pages.add(page);
      expect(req.url.queryParameters['game'], 'adofai');
      expect(req.url.queryParameters['limit'], '50');
      return http.Response(
          jsonEncode({
            'mods': [
              {...quartz, 'slug': 'm$page'}
            ],
            'pagination': {'totalPages': 2},
          }),
          200);
    });
    final mods = await ModlistClient.fetchAll();
    expect(pages, ['1', '2']);
    expect(mods.map((m) => m.slug), ['m1', 'm2']);
  });

  test('downloadUri omits null gameVersion', () {
    expect(
        ModlistClient.downloadUri('quartz', loader: 'umm', platform: 'macos')
            .toString(),
        'https://modlist.org/api/mods/quartz/download?loader=umm&platform=macos');
    expect(
        ModlistClient.downloadUri('quartz',
                loader: 'umm', platform: 'macos', gameVersion: '2.9')
            .queryParameters['gameVersion'],
        '2.9');
  });
}
