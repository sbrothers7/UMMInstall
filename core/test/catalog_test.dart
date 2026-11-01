import 'dart:convert';

import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

ModlistMod theirs(String slug, {String summary = '', List<String> deps = const []}) =>
    ModlistMod.fromJson({
      'slug': slug,
      'name': slug,
      'summary': summary,
      'dependencies': deps,
    });

void main() {
  late http.Client saved;
  setUp(() => saved = httpClient);
  tearDown(() => httpClient = saved);

  final ours = [
    const Mod(id: 'Quartz', slug: 'quartz', url: 'u'),
    const Mod(id: 'Old', slug: 'old', url: 'u', v2: false),
  ];

  test('ours wins on slug collision', () {
    final c = Catalog.merge(ours, [theirs('quartz', summary: 'S'), theirs('x')]);
    expect(c.entries.map((e) => e.slug), ['old', 'quartz', 'x']);
    final q = c.find('quartz')!;
    expect(q.source, Source.modsJson);
    expect(q.name, 'Quartz');
    expect(q.summary, 'S');
    expect(q.theirs, isNotNull);
    expect(c.find('x')!.source, Source.modlist);
  });

  test('summary prefers modlist.org, else mods.json', () {
    final c = Catalog.merge(
      [
        const Mod(id: 'A', slug: 'a', url: 'u', summary: 'ours'),
        const Mod(id: 'B', slug: 'b', url: 'u', summary: 'ours'),
        const Mod(id: 'C', slug: 'c', url: 'u', summary: 'ours'),
        const Mod(id: 'D', slug: 'd', url: 'u'),
      ],
      [theirs('a', summary: 'theirs'), theirs('b')],
    );
    expect([for (final e in c.entries) e.summary], ['theirs', 'ours', 'ours', '']);
  });

  test('find is case-insensitive', () {
    expect(Catalog.merge(ours, []).find('Quartz')?.slug, 'quartz');
  });

  test('search matches summary', () {
    final c = Catalog.merge(ours, [theirs('x', summary: 'Hello World')]);
    expect(c.search('hello world').map((e) => e.slug), ['x']);
    expect(c.search('').length, 3);
  });

  test('gameVersions prefers modlist.org, else the mods.json builds', () {
    final c = Catalog.merge(
      [
        ...ours,
        const Mod(id: 'Both', slug: 'both', url: 'u'),
        const Mod(id: 'V2', slug: 'v2', url: 'u', v3: false),
      ],
      [
        const ModlistMod(slug: 'quartz', name: 'Quartz', gameVersions: ['3.4.0']),
        const ModlistMod(slug: 'both', name: 'Both'),
        const ModlistMod(slug: 'x', name: 'X'),
      ],
    );
    expect(c.find('quartz')!.gameVersions, ['3.4.0']);
    expect(c.find('both')!.gameVersions, ['2.x', '3.x']);
    expect(c.find('old')!.gameVersions, ['3.x']);
    expect(c.find('v2')!.gameVersions, ['2.x']);
    expect(c.find('x')!.gameVersions, isEmpty);
  });

  test('visibleOn hides v2:false on v2', () {
    final c = Catalog.merge(ours, [theirs('x')]);
    expect(c.find('old')!.visibleOn(true), false);
    expect(c.find('old')!.visibleOn(false), true);
    expect(c.find('old')!.visibleOn(null), true);
    expect(c.find('x')!.visibleOn(true), true);
  });

  final modsJson = jsonEncode({
    'mods': [
      {'id': 'Quartz', 'slug': 'quartz', 'url': 'u'}
    ]
  });

  test('Catalog.load keeps working when one source fails', () async {
    httpClient = MockClient((req) async => req.url.host == 'modlist.org'
        ? http.Response('x', 500)
        : http.Response(modsJson, 200));
    final c = await Catalog.load();
    expect(c.entries.map((e) => e.slug), ['quartz']);
    expect(c.warnings, hasLength(1));
    expect(c.warnings.single, startsWith('modlist.org unreachable: '));
  });

  test('Catalog.load throws when both fail', () async {
    httpClient = MockClient((req) async => http.Response('x', 500));
    expect(Catalog.load(), throwsA(isA<ModRegistryException>()));
  });
}
