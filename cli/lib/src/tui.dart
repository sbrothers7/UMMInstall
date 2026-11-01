import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';
import 'loader_commands.dart';
import 'mod_commands.dart';

enum MenuAction {
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
  int cursor;
  final Set<int> chosen;

  PickerState(this.rows, {this.multi = false, Set<int> preselected = const {}})
    : chosen = {...preselected},
      cursor = !multi && preselected.isNotEmpty ? preselected.first : 0;

  bool? handle(String key) {
    if (key == _up) cursor = (cursor - 1) % rows.length;
    if (key == _down) cursor = (cursor + 1) % rows.length;
    if (key == ' ' && multi && !chosen.add(cursor)) chosen.remove(cursor);
    if (_isEnter(key)) return true;
    if (key == 'q' || key == '\x1b') return false;
    return null;
  }

  String render(String title) {
    final b = StringBuffer('$title\n\n');
    for (var i = 0; i < rows.length; i++) {
      final box = multi ? (chosen.contains(i) ? '[x] ' : '[ ] ') : '';
      b.writeln('${i == cursor ? '> ' : '  '}$box${rows[i]}');
    }
    final hint = multi ? 'space toggle · enter confirm' : 'enter select';
    b.write('\n↑↓ move · $hint · q cancel');
    return b.toString();
  }
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

  /// Draws [s] and returns the keys given to it until [done] says stop.
  Future<bool> pick(PickerState st, String title) async {
    while (true) {
      draw(st.render(title));
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
    var cols = 80;
    try {
      cols = stdout.terminalColumns;
    } on StdoutException {
      // no window size (e.g. under `script`); keep 80
    }
    final pad = cols - left.length - right.length;
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

  Future<List<String>?> pickMethod() async {
    final linux = facts.os == 'linux';
    final names = linux ? ['ml'] : [for (final m in Method.values) m.name];
    final pre = linux ? 0 : Method.values.indexOf(c.config.defaultMethod);
    final st = PickerState(names, preselected: {pre});
    if (!await t.pick(st, 'Method')) return null;
    return [names[st.cursor]];
  }

  Future<List<String>?> pickMany(
    String title,
    List<String> rows,
    List<String> ids, {
    bool all = false,
  }) async {
    if (rows.isEmpty) return null;
    final st = PickerState(
      rows,
      multi: true,
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
        final m = await pickMethod();
        if (m == null) return;
        final method = Method.parse(m.first)!;
        await t.cookedFor(
          () => switch (a) {
            MenuAction.install => install(c, method: method),
            MenuAction.reinstall => reinstall(c, method: method),
            _ => setDefault(c, method.name),
          },
        );
      case MenuAction.uninstall:
        await t.cookedFor(() => uninstall(c));
      case MenuAction.list:
        await t.cookedFor(() => list(c));
      case MenuAction.search:
        final q = await t.cookedFor(() async {
          stdout.write('Search: ');
          return stdin.readLineSync()?.trim() ?? '';
        });
        if (q.isEmpty) return;
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
        final slugs = await pickMany(
          hits.isEmpty ? 'No mods match "$q"' : 'Install which?',
          [
            for (final e in hits)
              '${e.slug}  ${e.theirs?.version ?? e.ours?.version ?? '-'}  '
                  '${e.name}${e.jalib ? '  [broken]' : ''}',
          ],
          [for (final e in hits) e.slug],
        );
        if (slugs == null) return;
        await t.cookedFor(() => modinstall(c, slugs));
      case MenuAction.remove:
        final mods = [
          for (final m in ModStore.scanInstalled())
            p
                .basename(m.path)
                .replaceFirst(RegExp(r'\.dll$', caseSensitive: false), ''),
        ];
        final names = await pickMany('Remove which?', mods, mods);
        if (names == null) return;
        await t.cookedFor(() => remove(c, names));
      case MenuAction.upgrade:
        final ups = await upgrades();
        final slugs = await pickMany(
          ups.isEmpty ? 'Everything is up to date' : 'Upgrade which?',
          [for (final u in ups) '${u.entry.slug}  ${u.from ?? '?'} → ${u.to}'],
          [for (final u in ups) u.entry.slug],
          all: true,
        );
        if (slugs == null) return;
        await t.cookedFor(() => upgrade(c, slugs));
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
