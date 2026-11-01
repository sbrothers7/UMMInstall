import 'dart:io';

import 'package:amm/src/cli.dart';
import 'package:amm/src/context.dart';
import 'package:amm/src/tui.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (p.basenameWithoutExtension(Platform.executable) == 'ammtui') {
    exit(await runTui(Ctx()));
  }
  exit(await runCli(args));
}
