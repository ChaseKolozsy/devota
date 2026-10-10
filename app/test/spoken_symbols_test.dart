import 'package:devota/voice/spoken_symbols.dart';
import 'package:flutter_test/flutter_test.dart';

/// Symbols said by name while dictating.
void main() {
  String say(String heard, [String existing = '']) =>
      appendDictatedText(existing, heard);

  test('brackets hug what they enclose', () {
    expect(say('print open paren x close paren'), 'print(x)');
    expect(say('items open bracket zero close bracket'), 'items[zero]');
    expect(say('if x open curly brace close curly brace'), 'if x {}');
    expect(say('say open quote hi there close quote'), 'say "hi there"');
  });

  test('joiners join, operators are spaced', () {
    expect(say('snake underscore case dot py'), 'snake_case.py');
    expect(say('src forward slash main'), 'src/main');
    expect(say('x equals sign y plus sign one'), 'x = y + one');
    expect(say('echo dollar sign HOME'), r'echo $HOME');
    expect(say('Open Paren done Close Paren'), '(done)');
  });

  test('prose stays prose', () {
    const prose = 'add a dash of salt, then quote me and wait a period';
    expect(say(prose), prose);
    expect(say('then push', 'Fix it.'), 'Fix it. then push');
  });

  test('a symbol at the end of one utterance joins the next', () {
    final first = say('print open paren');
    expect(first, 'print(');
    expect(say('x close paren', first), 'print(x)');
    expect(say('please', 'tests pass'), 'tests pass please');
  });
}
