import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';
import 'loader_commands.dart';
import 'mod_commands.dart';

enum MenuAction {
  status('Show status', 'S'),
  install('Install loader', 'i'),
  reinstall('Reinstall loader', 'R'),
  uninstall('Uninstall loader', 'U'),
  setDefault('Set default method', 'd'),
  list('List installed mods', 'l'),
  search('Search & install mods', 's'),
  remove('Remove mods', 'r'),
  upgrade('Upgrade mods', 'u'),
  quit('Quit', 'q');

  final String label;
  final String key;
  const MenuAction(this.label, this.key);
}

const _up = '\x1b[A';
const _down = '\x1b[B';

bool _isEnter(String k) => k == '\r' || k == '\n';

/// The main menu's cursor and drawing; no IO.
class MenuState {
  int selected = 0;

  /// True while an action (picker, command, "Press any key") owns the screen.
  bool busy = false;

  /// Whether a background update may redraw the menu now.
  bool get canRedraw => !busy;

  /// The chosen action for [key], or null when it only moved the cursor.
  MenuAction? handle(String key) {
    const all = MenuAction.values;
    if (key == _up) selected = (selected - 1) % all.length;
    if (key == _down) selected = (selected + 1) % all.length;
    if (_isEnter(key)) return all[selected];
    for (final a in all) {
      if (a.key == key) return a;
    }
    return null;
  }

  String render({
    required String header,
    required Map<MenuAction, String> notes,
  }) {
    final b = StringBuffer('$header\n\n');
    for (final a in MenuAction.values) {
      final mark = a == MenuAction.values[selected] ? '> ' : '  ';
      final note = notes[a];
      b.writeln(
        '$mark${a.label.padRight(24)}${a.key}${note == null ? '' : '   $note'}',
      );
    }
    b.write('\n↑↓ move · enter select · letter = shortcut');
    return b.toString();
  }
}

/// A pick-one or pick-many list; no IO. [handle] returns true when done, false
/// when cancelled, null otherwise.
class PickerState {
  final List<String> rows;
  final bool multi;
  final String? header; // column titles, lined up above the rows
  final List<String>? details; // one per row, shown for the highlighted one
  int cursor;
  int top = 0; // first row on screen
  final Set<int> chosen;

  PickerState(
    this.rows, {
    this.multi = false,
    this.header,
    this.details,
    Set<int> preselected = const {},
  }) : chosen = {...preselected},
       cursor = !multi && preselected.isNotEmpty ? preselected.first : 0;

  bool? handle(String key) {
    if (key == _up) cursor = (cursor - 1) % rows.length;
    if (key == _down) cursor = (cursor + 1) % rows.length;
    if (key == ' ' && multi && !chosen.add(cursor)) chosen.remove(cursor);
    if (_isEnter(key)) return true;
    if (key == 'q' || key == '\x1b') return false;
    return null;
  }

  /// Fits a [lines] x [cols] screen: the rows scroll to keep the cursor on
  /// it and long lines are cut.
  String render(String title, {int lines = 1 << 30, int cols = 1 << 30}) {
    final head = [
      ...title.split('\n'),
      '',
      if (header != null) '${multi ? '      ' : '  '}$header',
    ];
    final detail = details?[cursor];
    // The blank line, the detail and the hint take the rest.
    final room = max(1, lines - head.length - (detail == null ? 2 : 3));
    if (cursor < top) top = cursor;
    if (cursor >= top + room) top = cursor - room + 1;
    final hint = [
      '↑↓ move',
      multi ? 'space toggle · enter confirm' : 'enter select',
      'q cancel',
      if (rows.length > room) '${cursor + 1}/${rows.length}',
    ].join(' · ');
    return [
          ...head,
          for (var i = top; i < min(rows.length, top + room); i++)
            '${i == cursor ? '> ' : '  '}'
                '${multi ? (chosen.contains(i) ? '[x] ' : '[ ] ') : ''}${rows[i]}',
          '',
          ?detail,
          hint,
        ]
        .map(
          (l) => l.length < cols ? l : '${l.substring(0, max(0, cols - 2))}…',
        )
        .join('\n');
  }
}

/// The methods the picker offers on [f]'s machine (Linux: ml only; macOS
/// game v2: rosetta only) and the row to start on: [preselect] when offered.
({List<Method> methods, int selected}) methodChoices(
  GameFacts f, {
  required Method preselect,
}) {
  final methods = f.os == 'linux'
      ? [Method.ml]
      : f.isV2
      ? [Method.rosetta]
      : Method.values;
  final i = methods.indexOf(preselect);
  return (methods: methods, selected: i < 0 ? 0 : i);
}

// --- IO below: raw mode, drawing and key reading. ---

/// Splits a stdin chunk into keys: arrows stay whole, a lone ESC is esc.
List<String> _keys(String chunk) {
  final out = <String>[];
  final runes = chunk.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    if (runes[i] == 0x1b && i + 2 < runes.length && runes[i + 1] == 0x5b) {
      out.add(String.fromCharCodes(runes.sublist(i, i + 3)));
      i += 2;
    } else {
      out.add(String.fromCharCode(runes[i]));
    }
  }
  return out;
}

class _Terminal {
  final _queue = <String>[];
  Completer<void>? _waiting;
  late final StreamSubscription<List<int>> _sub;

  _Terminal() {
    _sub = stdin.listen((bytes) {
      _queue.addAll(_keys(utf8.decode(bytes, allowMalformed: true)));
      _waiting?.complete();
    });
  }

  Future<String> key() async {
    while (_queue.isEmpty) {
      _waiting = Completer<void>();
      await _waiting!.future;
    }
    return _queue.removeAt(0);
  }

  void raw() {
    stdin.echoMode = false;
    stdin.lineMode = false;
    stdout.write('\x1b[?25l');
  }

  void cooked() {
    stdout.write('\x1b[?25h');
    stdin.lineMode = true;
    stdin.echoMode = true;
  }

  /// Runs [fn] with the terminal in normal line mode and key reading paused,
  /// so the commands' own prompts (`readLineSync`) work.
  Future<T> cookedFor<T>(Future<T> Function() fn) async {
    _sub.pause();
    cooked();
    stdout.write('\x1b[2J\x1b[H');
    try {
      return await fn();
    } finally {
      raw();
      _sub.resume();
    }
  }

  void draw(String s) => stdout.write('\x1b[2J\x1b[H$s');

  /// The window size; 24x80 when there is none (e.g. under `script`).
  ({int lines, int cols}) size() {
    try {
      return (lines: stdout.terminalLines, cols: stdout.terminalColumns);
    } on StdoutException {
      return (lines: 24, cols: 80);
    }
  }

  /// Draws [s] and returns the keys given to it until [done] says stop.
  Future<bool> pick(PickerState st, String title) async {
    while (true) {
      final s = size();
      draw(st.render(title, lines: s.lines, cols: s.cols));
      final r = st.handle(await key());
      if (r != null) return r;
    }
  }

  Future<void> close() => _sub.cancel();
}

String _loaderLabel(LoaderKind k) => switch (k) {
  LoaderKind.melonLoader => 'MelonLoader',
  LoaderKind.umm => 'UMM',
  LoaderKind.none => 'no loader',
};

/// The full-screen menu over the same commands as `amm`.
Future<int> runTui(Ctx c) async {
  // hasTerminal is also true for /dev/null, so probe the real thing.
  var tty = stdin.hasTerminal;
  if (tty) {
    try {
      stdin.echoMode = stdin.echoMode;
    } on StdinException {
      tty = false;
    }
  }
  if (!tty) {
    c.out.line('ammtui needs a terminal.');
    return 1;
  }
  final t = _Terminal();
  final menu = MenuState();
  final notes = <MenuAction, String>{};
  Catalog? catalog;
  var facts = await c.facts();
  var done = false;

  void redraw() {
    final left = 'ADOFAI Mod Manager';
    final right = [
      if (facts.version != null) 'v${facts.version}',
      _loaderLabel(facts.loader),
      'default: ${c.config.defaultMethod.name}',
    ].join(' · ');
    final pad = t.size().cols - left.length - right.length;
    t.draw(
      menu.render(
        header: '$left${' ' * (pad < 2 ? 2 : pad)}$right',
        notes: notes,
      ),
    );
  }

  Future<List<Upgrade>> upgrades() async {
    final cat = catalog;
    if (cat == null || !facts.found || facts.loader == LoaderKind.none) {
      return [];
    }
    return ModOps.upgrades(
      cat,
      AmmRecord.load(facts.gamePath),
      ModStore.scanInstalled(),
      targetFor(facts),
    ).upgrades;
  }

  Future<void> refreshNotes() async {
    notes[MenuAction.list] = facts.found
        ? '(${ModStore.scanInstalled().length} installed)'
        : '';
    if (notes[MenuAction.list]!.isEmpty) notes.remove(MenuAction.list);
    final n = (await upgrades()).length;
    if (catalog != null) notes[MenuAction.upgrade] = '($n updates)';
  }

  Future<Method?> pickMethod(Method preselect) async {
    final ch = methodChoices(facts, preselect: preselect);
    final st = PickerState(
      [for (final m in ch.methods) m.name],
      preselected: {ch.selected},
    );
    if (!await t.pick(st, 'Method')) return null;
    return ch.methods[st.cursor];
  }

  /// Runs a command in line mode; a catalog that can't be fetched is printed
  /// instead of thrown.
  Future<void> run(Future<int> Function() command) => t.cookedFor(() async {
    try {
      await command();
    } on ModRegistryException catch (e) {
      c.out.log(LogLevel.error, e.message);
    }
  });

  Future<void> say(String message) =>
      t.cookedFor(() async => c.out.line(message));

  Future<List<String>?> pickMany(
    String title,
    List<String> rows,
    List<String> ids, {
    bool all = false,
    String? header,
    List<String>? details,
  }) async {
    if (rows.isEmpty) return null;
    final st = PickerState(
      rows,
      multi: true,
      header: header,
      details: details,
      preselected: all ? {for (var i = 0; i < rows.length; i++) i} : const {},
    );
    if (!await t.pick(st, title) || st.chosen.isEmpty) return null;
    return [for (final i in st.chosen.toList()..sort()) ids[i]];
  }

  Future<void> act(MenuAction a) async {
    switch (a) {
      case MenuAction.quit:
        done = true;
        return;
      case MenuAction.install || MenuAction.reinstall || MenuAction.setDefault:
        // Reinstall starts on what is installed, so enter keeps it.
        final method = await pickMethod(
          a == MenuAction.reinstall && facts.loader != LoaderKind.none
              ? currentMethod(facts)
              : c.config.defaultMethod,
        );
        if (method == null) return;
        await run(
          () => switch (a) {
            MenuAction.install => install(c, method: method),
            MenuAction.reinstall => reinstall(c, method: method),
            _ => setDefault(c, method.name),
          },
        );
      case MenuAction.status:
        await run(() => status(c));
      case MenuAction.uninstall:
        await run(() => uninstall(c));
      case MenuAction.list:
        await run(() => list(c));
      case MenuAction.search:
        final q = await t.cookedFor(() async {
          stdout.write('Search (enter for all): ');
          return stdin.readLineSync()?.trim() ?? '';
        });
        t.draw('Searching...');
        final List<CatalogEntry> hits;
        try {
          hits = [
            for (final e in (await c.catalog()).search(q))
              if (e.visibleOn(facts.found ? facts.isV2 : null)) e,
          ];
        } catch (e) {
          await t.cookedFor(() async {
            c.out.line('Search failed: $e');
            return 1;
          });
          break;
        }
        if (hits.isEmpty) {
          await say('No mods match "$q".');
          break;
        }
        final table = catalogTable(hits);
        final slugs = await pickMany(
          'Install which?',
          table.sublist(1),
          [for (final e in hits) e.slug],
          header: table.first,
          details: [for (final e in hits) describe(e)],
        );
        if (slugs == null) return;
        await run(() => modinstall(c, slugs));
      case MenuAction.remove:
        final record = AmmRecord.load(facts.gamePath);
        final mods = ModStore.scanInstalled();
        final rows = [
          for (final m in mods)
            p
                .basename(m.path)
                .replaceFirst(RegExp(r'\.dll$', caseSensitive: false), ''),
        ];
        // A recorded mod is removed by its slug, so its record entry goes too.
        final ids = [
          for (final (i, m) in mods.indexed)
            record.ownerSlug(
                  p
                      .relative(m.path, from: facts.gamePath)
                      .replaceAll(p.separator, '/'),
                ) ??
                rows[i],
        ];
        final names = await pickMany('Remove which?', rows, ids);
        if (names == null) return;
        await run(() => remove(c, names.toSet().toList()));
      case MenuAction.upgrade:
        if (!facts.found || facts.loader == LoaderKind.none) {
          await run(() => upgrade(c, [])); // prints why
          break;
        }
        final List<Upgrade> ups;
        try {
          catalog ??= await c.catalog();
          ups = await upgrades();
        } on ModRegistryException catch (e) {
          await t.cookedFor(() async => c.out.log(LogLevel.error, e.message));
          break;
        }
        if (ups.isEmpty) {
          await say('All mods are up to date.');
          break;
        }
        final slugs = await pickMany(
          'Upgrade which?',
          [for (final u in ups) '${u.entry.slug}  ${u.from ?? '?'} → ${u.to}'],
          [for (final u in ups) u.entry.slug],
          all: true,
        );
        if (slugs == null) return;
        await run(() => upgrade(c, slugs));
    }
    stdout.write('\nPress any key to return.');
    await t.key();
    facts = await c.facts();
    await refreshNotes();
  }

  // Restore the terminal on Ctrl+C too.
  final sig = ProcessSignal.sigint.watch().listen((_) {
    t.cooked();
    exit(130);
  });
  try {
    t.raw();
    await refreshNotes();
    redraw();
    // The update count arrives when the catalog does; then the menu redraws.
    c
        .catalog()
        .then((cat) async {
          catalog = cat;
          await refreshNotes();
          if (!done && menu.canRedraw) redraw();
        })
        .catchError((_) {});
    while (!done) {
      final a = menu.handle(await t.key());
      if (a != null) {
        menu.busy = true;
        try {
          await act(a);
        } finally {
          menu.busy = false;
        }
      }
      if (!done) redraw();
    }
  } finally {
    await sig.cancel();
    t.cooked();
    stdout.write('\x1b[2J\x1b[H');
    await t.close();
  }
  return 0;
}
