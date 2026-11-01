import 'package:amm_core/amm_core.dart';

import 'config.dart';
import 'out.dart';

typedef RunScript =
    Future<int> Function({
      required ScriptCall call,
      required void Function(LogLevel, String) onLog,
      required void Function(String) onSubtitle,
    });

/// What every command needs; tests replace the pieces.
class Ctx {
  final Out out;
  final Config config;
  final Future<GameFacts> Function() facts;
  final RunScript runScript;
  final Future<Catalog> Function() catalog;
  final bool yes;

  Ctx({
    Out? out,
    Config? config,
    Future<GameFacts> Function()? facts,
    RunScript? runScript,
    Future<Catalog> Function()? catalog,
    this.yes = false,
  }) : out = out ?? Out.std(),
       config = config ?? Config.load(),
       facts = facts ?? GameFacts.detect,
       runScript = runScript ?? ScriptRunner.run,
       catalog = catalog ?? Catalog.load;
}
