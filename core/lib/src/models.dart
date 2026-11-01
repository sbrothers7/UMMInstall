enum LogLevel { info, ok, error, detail }

enum LoaderType { umm, melonLoader }

/// How a loader is installed: MelonLoader, native UMM, or UMM under Rosetta.
enum Method {
  ml,
  native,
  rosetta;

  /// Matches [name] case-insensitively; null when unknown.
  static Method? parse(String s) {
    final l = s.toLowerCase();
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
