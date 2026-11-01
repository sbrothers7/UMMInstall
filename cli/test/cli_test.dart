import 'package:amm/src/cli.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('normalize maps -l, -s, mi', () {
    expect(normalize(['-l']), ['list']);
    expect(normalize(['-s', 'x']), ['search', 'x']);
    expect(normalize(['mi', 'a']), ['modinstall', 'a']);
    expect(normalize(['list', '-l']), ['list', '-l']);
  });

  Future<(int, String)> run(List<String> argv) async {
    final env = testEnv();
    final code = await runCli(
      argv,
      makeCtx: (yes) => env.ctx(
        yes: yes,
        facts: env.facts(
          found: false,
          gamePath: '/nope',
          version: null,
          major: null,
        ),
      ),
    );
    return (code, env.sink.toString());
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
    final (code, text) = await run(['tui']);
    expect(code, 1);
    expect(text, contains('tui: not implemented yet'));
  });
}
