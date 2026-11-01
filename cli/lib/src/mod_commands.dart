import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';

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
  if (!f.found) {
    c.out.log(LogLevel.error, 'ADOFAI not found (looked in ${f.gamePath}).');
    return 1;
  }
  final record = AmmRecord.load(f.gamePath);
  final rows = <List<String>>[];
  for (final m in ModStore.scanInstalled()) {
    final rel = p.relative(m.path, from: f.gamePath).replaceAll(p.separator, '/');
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
    c.out.line('${e.slug}  $version  ${e.source.label}  $loaders  '
        '${e.name}$summary${e.jalib ? '  [broken: needs JALib]' : ''}');
  }
  return 0;
}
