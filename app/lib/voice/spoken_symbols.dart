/// Symbols said by name while dictating: "print open paren x close paren"
/// types `print(x)`.
///
/// Only names nobody says in an ordinary sentence are symbols ("open paren",
/// "underscore", "equals sign"); "dash", "period", "comma" and "quote" stay
/// words, since a prompt to an agent is mostly prose.
library;

/// [glueLeft]: no space before it. [callLike]: no space before it after a
/// word, as in `print(` and `items[`.
typedef _Symbol = ({
  String text,
  bool glueLeft,
  bool glueRight,
  bool callLike,
  bool word,
});

_Symbol _s(
  String text, {
  bool left = false,
  bool right = false,
  bool call = false,
  bool word = false,
}) =>
    (text: text, glueLeft: left, glueRight: right, callLike: call, word: word);

final _opening = <String>['open', 'left'];
final _closing = <String>['close', 'closing', 'right', 'end'];

Map<String, _Symbol> _buildSymbols() {
  final out = <String, _Symbol>{};
  void pair(List<String> names, String open, String close) {
    for (final name in names) {
      for (final o in _opening) {
        out['$o $name'] = _s(open, right: true);
      }
      for (final c in _closing) {
        out['$c $name'] = _s(close, left: true);
      }
    }
  }

  for (final name in ['paren', 'parens', 'parenthesis']) {
    for (final o in _opening) {
      out['$o $name'] = _s('(', right: true, call: true);
    }
    for (final c in _closing) {
      out['$c $name'] = _s(')', left: true);
    }
  }
  for (final o in _opening) {
    out['$o bracket'] = _s('[', right: true, call: true);
    out['$o square bracket'] = _s('[', right: true, call: true);
  }
  for (final c in _closing) {
    out['$c bracket'] = _s(']', left: true);
    out['$c square bracket'] = _s(']', left: true);
  }
  pair(['brace', 'curly brace', 'curly bracket'], '{', '}');
  pair(['angle bracket'], '<', '>');
  for (final o in _opening) {
    out['$o quote'] = _s('"', right: true);
  }
  for (final c in _closing) {
    out['$c quote'] = _s('"', left: true);
  }
  out.addAll({
    'single quote': _s("'"),
    'backtick': _s('`'),
    'back tick': _s('`'),
    'underscore': _s('_', left: true, right: true),
    'forward slash': _s('/', left: true, right: true),
    'backslash': _s(r'\', left: true, right: true),
    'back slash': _s(r'\', left: true, right: true),
    'hyphen': _s('-', left: true, right: true),
    'dot': _s('.', left: true, right: true),
    'pipe symbol': _s('|'),
    'vertical bar': _s('|'),
    'ampersand': _s('&'),
    'double ampersand': _s('&&'),
    'asterisk': _s('*'),
    'equals sign': _s('='),
    'plus sign': _s('+'),
    'minus sign': _s('-'),
    'less than sign': _s('<'),
    'greater than sign': _s('>'),
    'hash sign': _s('#', right: true),
    'pound sign': _s('#', right: true),
    'dollar sign': _s(r'$', right: true),
    'percent sign': _s('%', left: true),
    'at sign': _s('@', right: true),
    'tilde': _s('~', right: true),
    'caret': _s('^'),
    'colon': _s(':', left: true),
    'semicolon': _s(';', left: true),
    'question mark': _s('?', left: true),
    'exclamation mark': _s('!', left: true),
    'exclamation point': _s('!', left: true),
  });
  return out;
}

final _symbols = _buildSymbols();
final _longest = _symbols.keys
    .map((k) => k.split(' ').length)
    .reduce((a, b) => a > b ? a : b);

/// Characters a word dictated next attaches to with no space. Only openers:
/// a text ending in "." or "-" is just as often a finished sentence.
const _gluesRight = '([{<_/\\#\$@~';

/// [existing] Type-command text with the dictated [heard] appended, symbol
/// names written as symbols and spaced the way code is.
String appendDictatedText(String existing, String heard) {
  final words = heard.trim().split(RegExp(r'\s+'));
  final pieces = <_Symbol>[];
  var i = 0;
  while (i < words.length) {
    _Symbol? hit;
    var used = 0;
    for (var n = _longest; n >= 1 && hit == null; n--) {
      if (i + n > words.length) continue;
      final phrase = words
          .sublist(i, i + n)
          .map((w) => w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), ''))
          .join(' ');
      hit = _symbols[phrase];
      if (hit != null) used = n;
    }
    if (hit != null) {
      pieces.add(hit);
      i += used;
    } else {
      pieces.add(_s(words[i++], word: true));
    }
  }
  final out = StringBuffer(existing);
  var glue = existing.isEmpty || _openedSymbol(existing);
  var afterWord = existing.isNotEmpty && _endsInWord(existing);
  for (final piece in pieces) {
    if (piece.text.isEmpty) continue;
    final attach = piece.glueLeft || (piece.callLike && afterWord);
    if (!glue && !attach) out.write(' ');
    out.write(piece.text);
    glue = piece.glueRight;
    afterWord = piece.word;
  }
  return out.toString();
}

bool _endsInWord(String existing) =>
    RegExp(r'[A-Za-z0-9_]$').hasMatch(existing);

/// [existing] ends in a symbol the next word joins ("print(", "snake_").
bool _openedSymbol(String existing) {
  final last = existing[existing.length - 1];
  return _gluesRight.contains(last) && existing.trimRight() == existing;
}
