import 'dart:io';

import 'package:amm/src/cli.dart';
import 'package:amm/src/config.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/out.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalize maps -l, -s, mi', () {
    expect(normalize(['-l']), ['list']);
    expect(normalize(['-s', 'x']), ['search', 'x']);
    expect(normalize(['mi', 'a']), ['modinstall', 'a']);
    expect(normalize(['list', '-l']), ['list', '-l']);
  });

  Future<(int, String)> run(List<String> argv) async {
    final sink = StringBuffer();
    final tmp = Directory.systemTemp.createTempSync('amm_cli');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final code = await runCli(
      argv,
      makeCtx: (yes) => Ctx(
        out: Out(sink: sink),
        config: Config.load(env: {'XDG_CONFIG_HOME': tmp.path}),
        yes: yes,
        facts: () async => const GameFacts(
          os: 'macos', found: false, gamePath: '/nope', version: null,
          major: null, appleSilicon: true, hasArm64Slice: true,
          loader: LoaderKind.none,
        ),
      ),
    );
    return (code, sink.toString());
  }

  test('two method flags is a usage error', () async {
    expect((await run(['install', '--ml', '--native'])).$1, 2);
  });

  test('unknown command exits 2', () async {
    expect((await run(['frobnicate'])).$1, 2);
  });

  test('unknown flag exits 2', () async {
    expect((await run(['list', '--bogus'])).$1, 2);
  });

  test('help exits 0', () async {
    expect((await run(['help'])).$1, 0);
  });

  test('unimplemented command is stubbed', () async {
    final (code, text) = await run(['install', '--ml']);
    expect(code, 1);
    expect(text, contains('install: not implemented yet'));
  });
}
