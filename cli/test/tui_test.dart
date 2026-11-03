import 'package:amm/src/tui.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

const up = '\x1b[A';
const down = '\x1b[B';

void main() {
  test('shortcuts map case-sensitively', () {
    final m = MenuState();
    expect(m.handle('R'), MenuAction.reinstall);
    expect(m.handle('r'), MenuAction.remove);
    expect(m.handle('U'), MenuAction.uninstall);
    expect(m.handle('u'), MenuAction.upgrade);
    expect(m.handle('q'), MenuAction.quit);
    expect(m.handle('S'), MenuAction.status);
    expect(m.handle('s'), MenuAction.search);
    expect(m.handle('x'), isNull);
  });

  test('enter on launch shows status', () {
    expect(MenuState().handle('\r'), MenuAction.status);
  });

  test('down then enter selects second item', () {
    final m = MenuState();
    expect(m.handle(down), isNull);
    expect(m.handle('\r'), MenuAction.install);
  });

  test('selection wraps', () {
    final m = MenuState();
    m.handle(up);
    expect(m.handle('\n'), MenuAction.quit);
    m.handle(down);
    expect(m.selected, 0);
  });

  test('render marks the selected row with >', () {
    final m = MenuState()..handle(down);
    final rows = m.render(header: 'H', notes: {}).split('\n');
    expect(rows.where((r) => r.startsWith('> ')), hasLength(1));
    expect(
      rows.firstWhere((r) => r.startsWith('> ')),
      contains('Install loader'),
    );
    expect(m.render(header: 'H', notes: {}), contains('↑↓ move'));
  });

  test('render shows notes', () {
    final out = MenuState().render(
      header: 'H',
      notes: {
        MenuAction.list: '(3 installed)',
        MenuAction.upgrade: '(1 updates)',
      },
    );
    expect(out, contains('(3 installed)'));
    expect(out, contains('(1 updates)'));
  });

  test('background updates do not redraw while an action is busy', () {
    final m = MenuState();
    expect(m.canRedraw, isTrue);
    m.busy = true;
    expect(m.canRedraw, isFalse);
    m.busy = false;
    expect(m.canRedraw, isTrue);
  });

  test('picker space toggles in multi mode', () {
    final p = PickerState(['a', 'b'], multi: true);
    p.handle(' ');
    p.handle(down);
    p.handle(' ');
    p.handle(' ');
    expect(p.chosen, {0});
    expect(p.render('T'), contains('[x] a'));
  });

  GameFacts facts({String os = 'macos', int major = 3}) => GameFacts(
    os: os,
    found: true,
    gamePath: '/g',
    version: null,
    major: major,
    appleSilicon: true,
    hasArm64Slice: true,
    loader: LoaderKind.none,
  );

  test('methodChoices offers every method on v3 and preselects', () {
    final m = methodChoices(facts(), preselect: Method.native);
    expect(m.methods, Method.values);
    expect(m.selected, 1);
  });

  test('methodChoices offers only rosetta on macOS v2', () {
    final m = methodChoices(facts(major: 2), preselect: Method.ml);
    expect(m.methods, [Method.rosetta]);
    expect(m.selected, 0);
  });

  test('methodChoices offers ml and UMM on linux', () {
    final m = methodChoices(facts(os: 'linux'), preselect: Method.rosetta);
    expect(m.methods, [Method.ml, Method.rosetta]);
    expect(m.selected, 1);
  });

  test('picker scrolls to keep the cursor on screen', () {
    final p = PickerState([for (var i = 0; i < 10; i++) 'r$i']);
    // 8 lines: title, blank, 4 rows, blank, hint.
    var out = p.render('T', lines: 8);
    expect(out.split('\n'), hasLength(8));
    expect(out, allOf(contains('r0'), contains('r3'), isNot(contains('r4'))));
    expect(out, contains('1/10'));
    for (var i = 0; i < 5; i++) {
      p.handle(down);
    }
    out = p.render('T', lines: 8);
    expect(out, allOf(contains('r2'), contains('> r5'), isNot(contains('r6'))));
    expect(out, contains('6/10'));
    expect(PickerState(['a']).render('T', lines: 8), isNot(contains('1/1')));
  });

  test('picker cuts lines to the terminal width', () {
    final out = PickerState(['x' * 50], header: 'h' * 50).render('T', cols: 20);
    for (final l in out.split('\n')) {
      expect(l.length, lessThan(20));
    }
    expect(out, contains('…'));
  });

  test('picker header lines up with the rows', () {
    final out = PickerState(['a'], multi: true, header: 'H').render('T');
    expect(out.split('\n').sublist(0, 4), ['T', '', '      H', '> [ ] a']);
  });

  test('picker shows the highlighted row\'s details above the hint', () {
    final p = PickerState(['a', 'b'], details: ['A — first', 'B — second']);
    p.handle(down);
    final out = p.render('T', lines: 7).split('\n');
    expect(out, hasLength(7));
    expect(out.sublist(out.length - 2).first, 'B — second');
  });

  test('picker enter returns true, q returns false', () {
    final p = PickerState(['a', 'b'], preselected: {1});
    expect(p.cursor, 1);
    expect(p.handle(up), isNull);
    expect(p.handle('\r'), isTrue);
    expect(p.handle('q'), isFalse);
    expect(p.handle('\x1b'), isFalse);
  });
}
