import 'dart:io';

import 'package:amm/src/config.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/out.dart';
import 'package:amm_core/amm_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A sandbox every CLI test builds its [Ctx] from. It points the game path
/// and Steam folders at a temp dir, records script calls instead of running
/// them, and fails the test if anything touches the network. Teardown resets
/// the overrides.
class TestEnv {
  final Directory tmp;
  final Directory game;
  final StringBuffer sink = StringBuffer();

  /// Every script a command asked to run, in order.
  final List<ScriptCall> calls = [];

  /// The exit code the fake `runScript` returns.
  int scriptExit = 0;

  /// Times the default [httpClient] was used; any is a test failure.
  int httpCalls = 0;

  TestEnv._(this.tmp) : game = Directory('${tmp.path}/game')..createSync();

  Map<String, String> get configEnv => {
    'XDG_CONFIG_HOME': '${tmp.path}/config',
  };

  /// Facts for the temp game: v3 on Apple Silicon with the arm64 slice, no
  /// loader, unless told otherwise.
  GameFacts facts({
    String os = 'macos',
    bool found = true,
    String? gamePath,
    String? version = '3.4.0',
    int? major = 3,
    bool appleSilicon = true,
    bool hasArm64Slice = true,
    LoaderKind loader = LoaderKind.none,
  }) => GameFacts(
    os: os,
    found: found,
    gamePath: gamePath ?? game.path,
    version: version,
    major: major,
    appleSilicon: appleSilicon,
    hasArm64Slice: hasArm64Slice,
    loader: loader,
  );

  Ctx ctx({
    GameFacts? facts,
    bool yes = true,
    Catalog? catalog,
    Config? config,
  }) => Ctx(
    out: Out(sink: sink),
    config: config ?? Config.load(env: configEnv),
    facts: () async => facts ?? this.facts(),
    runScript: ({required call, required onLog, required onSubtitle}) async {
      calls.add(call);
      return scriptExit;
    },
    catalog: () async => catalog ?? Catalog([]),
    yes: yes,
  );
}

TestEnv testEnv() {
  final env = TestEnv._(Directory.systemTemp.createTempSync('amm_cli'));
  GamePaths.overrideGamePath(env.game.path);
  SteamConfig.overrideRoots(['${env.tmp.path}/steam']);
  httpClient = MockClient((req) async {
    env.httpCalls++;
    throw TestFailure('unexpected network call: ${req.url}');
  });
  addTearDown(() {
    GamePaths.overrideGamePath(null);
    SteamConfig.overrideRoots(null);
    httpClient = http.Client();
    env.tmp.deleteSync(recursive: true);
    expect(env.httpCalls, 0, reason: 'a test used the network');
  });
  return env;
}
