import 'mod_registry.dart';
import 'modlist.dart';

enum Source {
  modsJson,
  modlist;

  String get label => this == Source.modsJson ? 'mods.json' : 'modlist.org';
}

/// One installable mod, from mods.json and/or modlist.org.
class CatalogEntry {
  final String slug;
  final String name;
  final String summary;
  final Source source;
  final Mod? ours;
  final ModlistMod? theirs;

  CatalogEntry({required this.ours, required this.theirs})
      : slug = (ours?.slug ?? theirs!.slug).toLowerCase(),
        name = ours?.id ?? theirs!.name,
        summary = (theirs?.summary ?? '').isNotEmpty
            ? theirs!.summary
            : ours?.summary ?? '',
        source = ours != null ? Source.modsJson : Source.modlist;

  bool get jalib => ours?.jalib ?? false;
  List<String> get dependencies => theirs?.dependencies ?? const [];

  // Card details only modlist.org has; absent for mods.json-only entries.
  String? get author => theirs?.author;
  int? get downloads => theirs?.downloads;
  List<String> get categories => theirs?.categories ?? const [];
  String? get logo => theirs?.logo;

  /// Game versions the mod supports: modlist.org's when it lists some, else
  /// the builds mods.json allows.
  List<String> get gameVersions {
    final t = theirs?.gameVersions ?? const [];
    final o = ours;
    if (t.isNotEmpty || o == null) return t;
    return [if (o.v2) '2.x', if (o.v3) '3.x'];
  }

  /// Whether the mod works on the given game build (null = unknown, show it).
  bool visibleOn(bool? isV2) {
    final o = ours;
    if (isV2 == null || o == null) return true;
    return isV2 ? o.v2 : o.v3;
  }
}

/// mods.json merged with modlist.org; mods.json wins on a slug collision.
class Catalog {
  final List<CatalogEntry> entries;
  final List<String> warnings;

  Catalog(this.entries, [this.warnings = const []]);

  /// The MelonLoader plugins that load UMM mods (UMMBridge keeps the old
  /// `ummcompat` slug). The loader install sets one up; as a mod it would land
  /// in UMMMods/, and a second one starts UMM twice and crashes the game.
  static const compatPlugins = {'ummcompat', 'ummcompatrevival'};

  static Catalog merge(List<Mod> ours, List<ModlistMod> theirs,
      [List<String> warnings = const []]) {
    final bySlug = {
      for (final t in theirs)
        if (!compatPlugins.contains(t.slug.toLowerCase())) t.slug.toLowerCase(): t
    };
    final entries = [
      for (final o in ours)
        CatalogEntry(ours: o, theirs: bySlug.remove(o.slug.toLowerCase())),
      for (final t in bySlug.values) CatalogEntry(ours: null, theirs: t),
    ]..sort((a, b) => a.slug.compareTo(b.slug));
    return Catalog(entries, warnings);
  }

  /// Fetches both sources at once; one failing becomes a warning.
  static Future<Catalog> load() async {
    Future<(T?, String?)> attempt<T>(Future<T> f, String name) async {
      try {
        return (await f, null);
      } catch (e) {
        return (null, '$name unreachable: $e');
      }
    }

    final results = await Future.wait([
      attempt(ModRegistry.fetch(), 'mods.json'),
      attempt(ModlistClient.fetchAll(), 'modlist.org'),
    ]);
    final (mine, mineErr) = results[0] as (List<Mod>?, String?);
    final (their, theirErr) = results[1] as (List<ModlistMod>?, String?);
    if (mine == null && their == null) {
      throw ModRegistryException('$mineErr\n$theirErr');
    }
    return merge(mine ?? const [], their ?? const [], [?theirErr, ?mineErr]);
  }

  CatalogEntry? find(String slug) {
    final s = slug.toLowerCase();
    for (final e in entries) {
      if (e.slug == s) return e;
    }
    return null;
  }

  List<CatalogEntry> search(String query) {
    final q = query.toLowerCase();
    return [
      for (final e in entries)
        if (e.slug.contains(q) ||
            e.name.toLowerCase().contains(q) ||
            e.summary.toLowerCase().contains(q))
          e
    ];
  }
}
