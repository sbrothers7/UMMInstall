import 'dart:convert';

import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late http.Client saved;
  setUp(() => saved = httpClient);
  tearDown(() => httpClient = saved);

  test('isNewerVersion compares numerically and ignores v and suffixes', () {
    expect(isNewerVersion('v2.0.2', '2.0.1'), isTrue);
    expect(isNewerVersion('2.0.10', '2.0.9'), isTrue);
    expect(isNewerVersion('v2.1', '2.0.9'), isTrue);
    expect(isNewerVersion('v2.0.1', '2.0.1'), isFalse);
    expect(isNewerVersion('2.0.0', '2.0.1'), isFalse);
    expect(isNewerVersion('v2.0.1-beta', '2.0.1'), isFalse);
  });

  test('appVersion is a plain x.y.z', () {
    expect(appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('GithubRelease.latest reads the tag and assets', () async {
    httpClient = MockClient((req) async {
      expect(
        req.url.toString(),
        'https://api.github.com/repos/sbrothers7/UMMInstall/releases/latest',
      );
      return http.Response(
        jsonEncode({
          'tag_name': 'v9.9.9',
          'assets': [
            {'name': 'amm-linux-x64', 'browser_download_url': 'https://d/a'},
            {'name': 'Gui-macos.zip', 'browser_download_url': 'https://d/g'},
          ],
        }),
        200,
      );
    });
    final r = await GithubRelease.latest();
    expect(r.tag, 'v9.9.9');
    expect(r.assets, {'amm-linux-x64': 'https://d/a', 'Gui-macos.zip': 'https://d/g'});
  });

  test('GithubRelease.latest throws on an HTTP error', () async {
    httpClient = MockClient((_) async => http.Response('nope', 403));
    expect(GithubRelease.latest(), throwsA(anything));
  });
}
