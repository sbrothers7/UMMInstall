import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:args/args.dart';

import 'context.dart';
import 'loader_commands.dart';
import 'mod_commands.dart';

const _usage = '''
Usage: amm <command> [options]

Commands:
  install [--ml|--native|--rosetta]     Install a mod loader
  reinstall [--ml|--native|--rosetta]   Reinstall the loader
  uninstall                             Remove the loader
  default [ml|native|rosetta]           Show or set the default method
  list (-l)                             List installed mods
  search (-s) <query>                   Search the mod catalog
  modinstall (mi) <slug|url>...         Install mods
  mr <name>... [--keep]                 Remove mods
  upgrade [<name>...]                   Upgrade mods
  tui                                   Interactive mode
  help                                  Show this help

Global flags: -y/--yes (skip confirmations), -h/--help''';

const _methodFlags = ['ml', 'native', 'rosetta'];

/// Rewrites the short aliases in the first position.
List<String> normalize(List<String> argv) {
  if (argv.isEmpty) return argv;
  final first = switch (argv.first) {
    '-l' => 'list',
    '-s' => 'search',
    'mi' => 'modinstall',
    final other => other,
  };
  return [first, ...argv.skip(1)];
}

ArgParser _parser() {
  ArgParser cmd([List<String> flags = const []]) {
    final a = ArgParser()
      ..addFlag('yes', abbr: 'y', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false);
    for (final f in flags) {
      a.addFlag(f, negatable: false);
    }
    return a;
  }

  return ArgParser()
    ..addFlag('yes', abbr: 'y', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('install', cmd(_methodFlags))
    ..addCommand('reinstall', cmd(_methodFlags))
    ..addCommand('uninstall', cmd())
    ..addCommand('default', cmd())
    ..addCommand('list', cmd())
    ..addCommand('search', cmd())
    ..addCommand('modinstall', cmd())
    ..addCommand('mr', cmd(['keep']))
    ..addCommand('upgrade', cmd())
    ..addCommand('tui', cmd())
    ..addCommand('help', cmd());
}

Future<int> runCli(List<String> argv, {Ctx Function(bool yes)? makeCtx}) async {
  if (!Platform.isMacOS && !Platform.isLinux) {
    stderr.writeln('amm supports macOS and Linux only.');
    return 1;
  }
  int usageError(String msg) {
    stderr.writeln('$msg\n\n$_usage');
    return 2;
  }

  final ArgResults top;
  try {
    top = _parser().parse(normalize(argv));
  } on FormatException catch (e) {
    return usageError(e.message);
  }
  final cmd = top.command;
  if (cmd == null || cmd.name == 'help' || top['help'] as bool) {
    if (cmd == null && top.rest.isNotEmpty) {
      return usageError('Unknown command "${top.rest.first}".');
    }
    stdout.writeln(_usage);
    return 0;
  }
  if (cmd['help'] as bool) {
    stdout.writeln(_usage);
    return 0;
  }
  final methods = [
    for (final m in _methodFlags)
      if (cmd.options.contains(m) && cmd[m] as bool) m,
  ];
  if (methods.length > 1) {
    return usageError('Use only one of --ml, --native, --rosetta.');
  }
  final yes = (top['yes'] as bool) || (cmd['yes'] as bool);
  final name = cmd.name!;
  final c = (makeCtx ?? (yes) => Ctx(yes: yes))(yes);
  final method = methods.isEmpty ? null : Method.parse(methods.first);
  return switch (name) {
    'install' => install(c, method: method),
    'reinstall' => reinstall(c, method: method),
    'uninstall' => uninstall(c),
    'default' => setDefault(c, cmd.rest.firstOrNull),
    'list' => list(c),
    'search' when cmd.rest.isEmpty =>
      Future.value(usageError('search needs a query.')),
    'search' => search(c, cmd.rest.join(' ')),
    _ => _notImplemented(c, name),
  };
}

// Tasks 9-10 replace these.
Future<int> _notImplemented(Ctx c, String name) async {
  c.out.line('$name: not implemented yet');
  return 1;
}
