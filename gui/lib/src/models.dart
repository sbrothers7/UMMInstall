// Core enums and small value types, ported from the macOS SwiftUI app.

enum LogLevel { info, ok, error, detail }

enum Language { en, ko }

enum LoaderType { umm, melonLoader }

enum InstallPhase {
  updating,
  confirm,
  needsVerify,
  installed,
  picker,
  manageMods,
  installingBrew,
  installing,
  uninstalling,
  migrating,
  confirmModMove,
  complete,
}

/// A mod found on disk in the game's mods folder(s).
class InstalledMod {
  final String name;
  final String path;
  final bool isDirectory;

  const InstalledMod({
    required this.name,
    required this.path,
    required this.isDirectory,
  });
}

/// A mod that was soft-deleted ("Keep Data") into the persistent archive, with
/// enough info to restore it to its original location.
class ArchivedMod {
  final String name;
  final String key; // archive subfolder name
  final String originPath; // where to restore it to
  final bool isDirectory;
  final String payloadPath; // the preserved item inside the archive

  const ArchivedMod({
    required this.name,
    required this.key,
    required this.originPath,
    required this.isDirectory,
    required this.payloadPath,
  });
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
