import 'package:amm/src/cli.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('normalize maps -l, -s, mi', () {
    expect(normalize(['-l']), ['list']);
    expect(normalize(['-s', 'x']), ['search', 'x']);
    expect(normalize(['mi', 'a']), ['install', '--mod', 'a']);
    expect(normalize(['modinstall', 'a', 'b']), ['install', '--mod', 'a', 'b']);
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

  test('install --mod reaches mod install', () async {
    final (code, out) = await run(['install', '--mod', 'x']);
    expect(code, 1);
    expect(out, contains('ADOFAI not found'));
  });

  test('install --mod needs a mod and no loader flag', () async {
    expect((await run(['install', '--mod'])).$1, 2);
    expect((await run(['install', '--mod', '--ml', 'x'])).$1, 2);
  });

  test('search without a query is allowed', () async {
    expect((await run(['search'])).$1, 0);
    expect((await run(['-s'])).$1, 0);
  });

  test('status runs without a game and exits 1', () async {
    final (code, out) = await run(['status']);
    expect(code, 1);
    expect(out, contains('ADOFAI not found (looked in /nope).'));
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

  test('search exits 1 cleanly when both sources fail', () async {
    final env = testEnv();
    final code = await runCli(
      ['search', 'x'],
      makeCtx: (yes) => env.ctx(
        yes: yes,
        catalogError: ModRegistryException(
          'mods.json unreachable: a\nmodlist.org unreachable: b',
        ),
      ),
    );
    expect(code, 1);
    expect(
      env.sink.toString(),
      '✗ mods.json unreachable: a\nmodlist.org unreachable: b\n',
    );
  });

  test('tui ignores -y', () async {
    bool? yes;
    // Stop before the TUI itself runs; only the ctx it gets matters.
    await expectLater(
      runCli(
        ['-y', 'tui'],
        makeCtx: (y) {
          yes = y;
          throw StateError('stop');
        },
      ),
      throwsStateError,
    );
    expect(yes, isFalse);
  });
}
