import 'dart:io';

import 'package:amm_core/amm_core.dart';

/// All user-facing output and prompts. The only place that emits ANSI codes.
class Out {
  final StringSink _sink;
  final bool color;
  final bool interactive;
  final String? Function() _readLine;

  Out({
    StringSink? sink,
    this.color = false,
    this.interactive = false,
    String? Function()? readLine,
  })  : _sink = sink ?? stdout,
        _readLine = readLine ?? stdin.readLineSync;

  factory Out.std() => Out(
        color: stdout.hasTerminal,
        interactive: stdin.hasTerminal,
      );

  String _wrap(String code, String s) => color ? '\x1b[${code}m$s\x1b[0m' : s;

  void log(LogLevel level, String msg) {
    line(switch (level) {
      LogLevel.info => msg,
      LogLevel.ok => _wrap('32', '✓ $msg'),
      LogLevel.error => _wrap('31', '✗ $msg'),
      LogLevel.detail => _wrap('2', '    $msg'),
    });
  }

  void subtitle(String s) => line(_wrap('1', s));

  void line(String s) => _sink.writeln(s);

  /// Asks [question]; [yes] answers it without prompting. Refuses when there
  /// is no terminal to ask on.
  bool confirm(String question, {required bool yes}) {
    if (yes) return true;
    if (!interactive) {
      line('Pass -y to confirm without a prompt.');
      return false;
    }
    _sink.write('$question [y/N] ');
    final a = _readLine()?.trim().toLowerCase();
    return a == 'y' || a == 'yes';
  }
}
