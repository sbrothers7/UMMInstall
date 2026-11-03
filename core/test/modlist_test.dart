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
  'authorId': {'username': 'koren.cs'},
  'downloads': 317,
  'categories': ['utility', 'gameplay'],
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

  test('fromJson reads author, downloads and categories', () {
    final m = ModlistMod.fromJson(quartz);
    expect(m.author, 'koren.cs');
    expect(m.downloads, 317);
    expect(m.categories, ['utility', 'gameplay']);
  });

  test('fromJson resolves the logo path against modlist.org', () {
    expect(ModlistMod.fromJson({...quartz, 'logo': '/logos/a.webp'}).logo,
        'https://modlist.org/logos/a.webp');
    expect(ModlistMod.fromJson(quartz).logo, isNull);
  });

  test('fromJson tolerates missing fields', () {
    final m = ModlistMod.fromJson({'slug': 's', 'name': 'S', 'latestVersion': null});
    expect(m.summary, '');
    expect(m.version, isNull);
    expect(m.dependencies, isEmpty);
    expect(m.loaders, isEmpty);
    expect(m.gameVersions, isEmpty);
    expect(m.author, isNull);
    expect(m.downloads, 0);
    expect(m.categories, isEmpty);
  });

  test('fromJson reads game versions, falling back to gameVersion', () {
    ModlistMod mod(Map<String, dynamic> latest) =>
        ModlistMod.fromJson({'slug': 's', 'name': 'S', 'latestVersion': latest});
    expect(
      mod({
        'gameVersion': '2.9.5-2.9.8, 3.1.0-3.4.0',
        'availableGameVersions': ['2.9.5-2.9.8', '3.1.0-3.4.0'],
      }).gameVersions,
      ['2.9.5-2.9.8', '3.1.0-3.4.0'],
    );
    expect(mod({'gameVersion': '2.9.8+'}).gameVersions, ['2.9.8+']);
    expect(mod({'gameVersion': '', 'availableGameVersions': []}).gameVersions, isEmpty);
    expect(ModlistMod.fromJson(quartz).gameVersions, isEmpty);
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

  test('fetchAll drops entries with unsafe slugs', () async {
    httpClient = MockClient((_) async => http.Response(
        jsonEncode({
          'mods': [
            for (final s in ['good-1.x', '../evil', 'a/b', 'Upper', '', '.hidden'])
              {...quartz, 'slug': s}
          ],
          'pagination': {'totalPages': 1},
        }),
        200));
    expect((await ModlistClient.fetchAll()).map((m) => m.slug), ['good-1.x']);
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
