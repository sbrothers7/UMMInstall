import 'package:amm/src/out.dart';
import 'package:amm_core/amm_core.dart';
import 'package:test/test.dart';

void main() {
  test('confirm refuses without a terminal', () {
    final sink = StringBuffer();
    final out = Out(sink: sink, interactive: false);
    expect(out.confirm('Sure?', yes: false), isFalse);
    expect(sink.toString(), contains('Pass -y'));
  });

  test('confirm accepts y', () {
    final sink = StringBuffer();
    final out = Out(sink: sink, interactive: true, readLine: () => 'y');
    expect(out.confirm('Sure?', yes: false), isTrue);
    expect(sink.toString(), contains('Sure? [y/N] '));
  });

  test('confirm rejects anything else', () {
    final out = Out(sink: StringBuffer(), interactive: true, readLine: () => '');
    expect(out.confirm('Sure?', yes: false), isFalse);
  });

  test('confirm with yes skips the prompt', () {
    final sink = StringBuffer();
    expect(Out(sink: sink).confirm('Sure?', yes: true), isTrue);
    expect(sink.toString(), isEmpty);
  });

  test('log prefixes', () {
    final sink = StringBuffer();
    Out(sink: sink)
      ..log(LogLevel.info, 'a')
      ..log(LogLevel.ok, 'b')
      ..log(LogLevel.error, 'c')
      ..log(LogLevel.detail, 'd');
    expect(sink.toString(), 'a\n✓ b\n✗ c\n    d\n');
  });

  test('color wraps ok in green', () {
    final sink = StringBuffer();
    Out(sink: sink, color: true).log(LogLevel.ok, 'b');
    expect(sink.toString(), contains('\x1b[32m'));
  });
}
