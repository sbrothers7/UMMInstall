import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:args/args.dart';

import 'context.dart';
import 'loader_commands.dart';
import 'mod_commands.dart';
import 'tui.dart';
import 'update_command.dart';

const _usage = '''
Usage: amm <command> [options]

Commands:
  install [--ml|--native|--rosetta|--umm]     Install a mod loader
  reinstall [--ml|--native|--rosetta|--umm]   Reinstall the loader
  uninstall                                   Remove the loader
  default [ml|native|rosetta|umm]             Show or set the default method
  status                                      Show the game, loader and mods
  list (-l)                                   List installed mods
  search (-s) [<query>]                       Search the mod catalog (all if no query)
  install --mod <slug>... (mi)                Install mods
  mr <name>... [--keep]                       Remove mods
  upgrade [<name>...]                         Upgrade mods
  update                                      Update the CLI, TUI and GUI app
  auto-update [on|off]                        Show or set automatic updates
  tui                                         Interactive mode
  help                                        Show this help

--umm is the classic UMM patch, another name for --rosetta. Only an Apple
Silicon Mac runs it under Rosetta.

amm updates itself and the GUI once a day before a command; turn that off
with `amm auto-update off` or AMM_NO_AUTO_UPDATE=1.

Global flags: -y/--yes (skip confirmations), -h/--help''';

const _methodFlags = ['ml', 'native', 'rosetta', 'umm'];

/// Rewrites the short aliases in the first position.
List<String> normalize(List<String> argv) {
  if (argv.isEmpty) return argv;
  final first = switch (argv.first) {
    '-l' => ['list'],
    '-s' => ['search'],
    'mi' || 'modinstall' => ['install', '--mod'],
    final other => [other],
  };
  return [...first, ...argv.skip(1)];
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
    ..addCommand('install', cmd([..._methodFlags, 'mod']))
    ..addCommand('reinstall', cmd(_methodFlags))
    ..addCommand('uninstall', cmd())
    ..addCommand('default', cmd())
    ..addCommand('status', cmd())
    ..addCommand('list', cmd())
    ..addCommand('search', cmd())
    ..addCommand('mr', cmd(['keep']))
    ..addCommand('upgrade', cmd())
    ..addCommand('update', cmd())
    ..addCommand('auto-update', cmd())
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
    return usageError('Use only one of --ml, --native, --rosetta, --umm.');
  }
  final yes = (top['yes'] as bool) || (cmd['yes'] as bool);
  final name = cmd.name!;
  // The TUI's prompts are always asked; -y must not answer them.
  final c = (makeCtx ?? (yes) => Ctx(yes: yes))(yes && name != 'tui');
  final method = methods.isEmpty ? null : Method.parse(methods.first);
  final mod = cmd.options.contains('mod') && cmd['mod'] as bool;
  // The TUI checks on its own, before it takes over the screen.
  if (!const {'update', 'auto-update', 'tui'}.contains(name) &&
      await autoUpdate(c)) {
    return relaunch(argv);
  }
  try {
    return await switch (name) {
      'install' when mod && methods.isNotEmpty => Future.value(
        usageError('Use --mod without --ml, --native, --rosetta or --umm.'),
      ),
      'install' when mod && cmd.rest.isEmpty => Future.value(
        usageError('install --mod needs at least one mod.'),
      ),
      'install' when mod => modinstall(c, cmd.rest),
      'install' => install(c, method: method),
      'reinstall' => reinstall(c, method: method),
      'uninstall' => uninstall(c),
      'default' => setDefault(c, cmd.rest.firstOrNull),
      'status' => status(c),
      'list' => list(c),
      'search' => search(c, cmd.rest.join(' ')),
      'mr' when cmd.rest.isEmpty => Future.value(
        usageError('mr needs at least one mod.'),
      ),
      'mr' => remove(c, cmd.rest, keep: cmd['keep'] as bool),
      'upgrade' => upgrade(c, cmd.rest),
      'update' => update(c),
      'auto-update' => setAutoUpdate(c, cmd.rest.firstOrNull),
      'tui' => runTui(c),
      _ => usageError('Unknown command "$name".'),
    };
  } on ModRegistryException catch (e) {
    // Neither catalog source could be reached.
    c.out.log(LogLevel.error, e.message);
    return 1;
  }
}
