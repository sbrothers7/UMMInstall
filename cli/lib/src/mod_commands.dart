import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';
import 'loader_commands.dart' show gameFound;

/// `amm default [ml|native|rosetta]`.
Future<int> setDefault(Ctx c, String? value) async {
  if (value != null) {
    final m = Method.parse(value);
    if (m == null) {
      c.out.line('Unknown method "$value". Use ml, native or rosetta.');
      return 2;
    }
    if ((await c.facts()).os == 'linux' && m != Method.ml) {
      c.out.log(LogLevel.error, 'On Linux only MelonLoader is supported.');
      return 1;
    }
    c.config.defaultMethod = m;
    c.config.save();
  }
  c.out.line('default: ${c.config.defaultMethod.name}');
  return 0;
}

/// `amm list`: installed mods; reads the disk only.
Future<int> list(Ctx c) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  final record = AmmRecord.load(f.gamePath);
  final rows = <List<String>>[];
  for (final m in ModStore.scanInstalled()) {
    final rel = p
        .relative(m.path, from: f.gamePath)
        .replaceAll(p.separator, '/');
    final owner = record.ownerOf(rel);
    rows.add([
      m.name,
      owner?.version ??
          (m.isDirectory ? ModStore.infoField(m.path, 'Version') : null) ??
          '-',
      p.basename(p.dirname(m.path)),
      owner?.source ?? '-',
    ]);
  }
  for (final line in _table(rows)) {
    c.out.line(line);
  }
  final archived = ModStore.scanArchived().length;
  if (archived > 0) c.out.line('$archived archived (restore them in the GUI)');
  return 0;
}

/// Columns joined by two spaces, padded to the widest value, last unpadded.
List<String> _table(List<List<String>> rows) {
  if (rows.isEmpty) return [];
  final cols = rows.first.length;
  final w = [
    for (var i = 0; i < cols - 1; i++)
      rows.map((r) => r[i].length).reduce((a, b) => a > b ? a : b),
  ];
  return [
    for (final r in rows)
      [for (var i = 0; i < cols; i++) i < cols - 1 ? r[i].padRight(w[i]) : r[i]]
          .join('  '),
  ];
}

/// `amm search <query>`: the one command here that uses the network.
Future<int> search(Ctx c, String query) async {
  final cat = await c.catalog();
  for (final w in cat.warnings) {
    c.out.line(w);
  }
  final f = await c.facts();
  final hits = [
    for (final e in cat.search(query))
      if (e.visibleOn(f.found ? f.isV2 : null)) e,
  ];
  if (hits.isEmpty) {
    c.out.line('No mods match "$query".');
    return 0;
  }
  for (final e in hits) {
    final l = e.theirs?.loaders ?? const <String>{};
    final loaders = l.isEmpty
        ? 'any'
        : [
            if (l.contains('melonloader')) 'ml',
            if (l.contains('umm')) 'umm',
          ].join(',');
    final version = e.theirs?.version ?? e.ours?.version ?? '-';
    final summary = e.summary.isEmpty ? '' : ' — ${e.summary}';
    c.out.line(
      '${e.slug}  $version  ${e.source.label}  $loaders  '
      '${e.name}$summary${e.jalib ? '  [broken: needs JALib]' : ''}',
    );
  }
  return 0;
}

/// Where [f]'s game takes mods.
ModTarget targetFor(GameFacts f) => ModTarget(
  gameRoot: f.gamePath,
  isV2: f.isV2,
  gameVersion: f.version,
  melon: f.loader == LoaderKind.melonLoader,
  platform: f.os,
);

/// The game's facts when it is there and has a loader, else null after
/// printing why.
Future<GameFacts?> _readyGame(Ctx c) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return null;
  if (f.loader == LoaderKind.none) {
    c.out.log(
      LogLevel.error,
      'No mod loader installed. Run `amm install` first.',
    );
    return null;
  }
  return f;
}

/// Runs [job] with a progress line, then prints `✓`/`✗` for [slug]; true on
/// success. Core's two expected failures are reported, anything else rethrown.
Future<bool> _step(
  Ctx c,
  String slug,
  Future<RecordEntry> Function(void Function(double)) job,
  void Function(RecordEntry) onDone,
) async {
  try {
    c.out.progress(slug, null);
    final e = await job((x) => c.out.progress(slug, x));
    c.out.clearProgress();
    onDone(e);
    c.out.log(LogLevel.ok, '$slug ${e.version ?? ''}'.trimRight());
    return true;
  } on ModOpsException catch (e) {
    c.out.clearProgress();
    c.out.log(LogLevel.error, '$slug: ${e.message}');
  } on ModDownloadException catch (e) {
    c.out.clearProgress();
    c.out.log(LogLevel.error, '$slug: ${e.message}');
  }
  return false;
}

/// `amm modinstall <slug>...`.
Future<int> modinstall(Ctx c, List<String> slugs) async {
  final f = await _readyGame(c);
  if (f == null) return 1;
  final cat = await c.catalog();
  for (final w in cat.warnings) {
    c.out.line(w);
  }
  final record = AmmRecord.load(f.gamePath);
  final plan = ModOps.plan(cat, slugs, record);
  if (plan.missing.isNotEmpty) {
    c.out.line('Unknown mod(s): ${plan.missing.join(', ')}. Try `amm search`.');
    return 1;
  }
  final asked = {for (final s in slugs) s.toLowerCase()};
  c.out.line(
    'Installing: ${[for (final e in plan.order) asked.contains(e.slug) ? e.slug : '${e.slug} (dependency)'].join(', ')}',
  );
  final target = targetFor(f);
  var failed = false;
  for (final e in plan.order) {
    final ok = await _step(
      c,
      e.slug,
      (p) => ModOps.install(e, target, onProgress: p),
      (r) {
        record.mods[e.slug] = r;
        record.save(f.gamePath);
      },
    );
    failed |= !ok;
  }
  return failed ? 1 : 0;
}

/// `amm mr <name>... [--keep]`.
Future<int> remove(Ctx c, List<String> slugs, {bool keep = false}) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  final list = slugs.join(', ');
  final question = keep
      ? 'Archive ${slugs.length} mod(s): $list? You can restore them in the GUI.'
      : 'Delete ${slugs.length} mod(s): $list?';
  if (!c.out.confirm(question, yes: c.yes)) return 1;
  final record = AmmRecord.load(f.gamePath);
  var failed = false;
  for (final s in slugs) {
    try {
      final paths = ModOps.remove(s, record, f.gamePath, keep: keep);
      c.out.log(
        LogLevel.ok,
        '$s: ${keep ? 'archived' : 'removed'} ${paths.join(', ')}',
      );
    } on ModOpsException catch (e) {
      c.out.log(LogLevel.error, e.message);
      failed = true;
    }
  }
  record.save(f.gamePath);
  return failed ? 1 : 0;
}

/// `amm upgrade [<name>...]`; no names means everything.
Future<int> upgrade(Ctx c, List<String> slugs) async {
  final f = await _readyGame(c);
  if (f == null) return 1;
  final cat = await c.catalog();
  for (final w in cat.warnings) {
    c.out.line(w);
  }
  final record = AmmRecord.load(f.gamePath);
  final target = targetFor(f);
  final scan = ModOps.upgrades(cat, record, ModStore.scanInstalled(), target);
  final asked = {for (final s in slugs) s.toLowerCase()};
  final todo = [
    for (final u in scan.upgrades)
      if (asked.isEmpty || asked.contains(u.entry.slug)) u,
  ];
  for (final s in asked) {
    if (!todo.any((u) => u.entry.slug == s)) c.out.line('$s is up to date.');
  }
  if (todo.isEmpty && asked.isEmpty) c.out.line('All mods are up to date.');
  if (todo.isNotEmpty) {
    c.out.line(
      'Upgrading: ${[for (final u in todo) '${u.entry.slug} ${u.from ?? '?'} → ${u.to}'].join(', ')}',
    );
  }
  var failed = false;
  for (final u in todo) {
    final ok = await _step(
      c,
      u.entry.slug,
      (p) => ModOps.upgrade(u, target, onProgress: p),
      (r) {
        record.mods[u.entry.slug] = r;
        record.save(f.gamePath);
      },
    );
    failed |= !ok;
  }
  if (scan.unknown.isNotEmpty) {
    c.out.line('Skipped (unknown source): ${scan.unknown.join(', ')}');
  }
  return failed ? 1 : 0;
}
