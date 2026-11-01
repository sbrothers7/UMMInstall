import 'package:test/test.dart';

import 'package:amm_core/amm_core.dart';

void main() {
  test('Mod.resolvedUrl prefers MelonLoader, then v2, then default', () {
    const mod = Mod(
      id: 'Test',
      slug: 'test',
      url: 'default',
      urlV2: 'v2',
      urlMelon: 'melon',
    );
    expect(mod.resolvedUrl(isGameV2: false, isMelonLoader: true), 'melon');
    expect(mod.resolvedUrl(isGameV2: true, isMelonLoader: false), 'v2');
    expect(mod.resolvedUrl(isGameV2: false, isMelonLoader: false), 'default');
  });

  test('Mod.fromJson applies defaults', () {
    final mod = Mod.fromJson({'id': 'X', 'url': 'u'});
    expect(mod.v2, true);
    expect(mod.v3, true);
    expect(mod.jalib, false);
    expect(mod.install, isNull);
  });

  test('Mod.slug falls back to lowercased id', () {
    expect(Mod.fromJson({'id': 'AbC', 'url': 'u'}).slug, 'abc');
    expect(Mod.fromJson({'id': 'AbC', 'slug': 'jrp', 'url': 'u'}).slug, 'jrp');
  });

  test('Mod.resolvedVersion mirrors resolvedUrl', () {
    const mod = Mod(
      id: 'T',
      slug: 't',
      url: 'd',
      urlV2: 'v2',
      urlMelon: 'm',
      version: '1',
      versionMelon: '2',
    );
    expect(mod.resolvedVersion(isGameV2: false, isMelonLoader: true), '2');
    expect(mod.resolvedVersion(isGameV2: true, isMelonLoader: false), isNull);
    expect(mod.resolvedVersion(isGameV2: false, isMelonLoader: false), '1');
  });
}
