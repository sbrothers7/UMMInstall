// GUI-only enums and types, ported from the macOS SwiftUI app.
import 'package:amm_core/amm_core.dart' show LogLevel;

enum Language { en, ko }

enum InstallPhase {
  updating,
  confirm,
  needsVerify,
  installed,
  mods,
  installingBrew,
  installing,
  uninstalling,
  migrating,
  confirmModMove,
  complete,
}

class LogEntry {
  final int id;
  LogLevel level;
  String message;

  /// null: a normal log line. >= 0: a determinate progress bar (0..1).
  /// < 0: an indeterminate progress bar (total size unknown).
  double? progress;

  LogEntry(this.level, this.message, {this.progress}) : id = _nextId++;

  static int _nextId = 0;
}
