import 'record.dart';

enum LogLevel { info, ok, error, detail }

enum LoaderType { umm, melonLoader }

/// How a loader is installed: MelonLoader, native UMM, or UMM under Rosetta.
enum Method {
  ml,
  native,
  rosetta;

  /// Matches [name] case-insensitively; null when unknown. `umm` names the
  /// classic UMM patch, which is the rosetta method without Rosetta on an
  /// Intel Mac or Linux.
  static Method? parse(String s) {
    final l = s.toLowerCase();
    if (l == 'umm') return rosetta;
    for (final m in values) {
      if (m.name == l) return m;
    }
    return null;
  }
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

  /// (where to restore it to, the preserved copy inside the archive): one
  /// pair for a file or folder, one per path for a recorded mod.
  final List<(String, String)> items;

  /// Set for a recorded mod: its slug and record entry, put back on restore.
  final String? slug;
  final RecordEntry? record;

  const ArchivedMod({
    required this.name,
    required this.key,
    required this.items,
    this.slug,
    this.record,
  });
}
