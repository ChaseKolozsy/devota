/// Vim by voice, while vim mode is on ("vim mode" / "vim off").
///
/// Every command starts with Ctrl-\ Ctrl-N, vim's own "to Normal mode from
/// any mode". Escape would do the same from insert mode, but Escape followed
/// at once by a key reaches vim through tmux as Alt plus that key.
library;

import 'voice_commands.dart';

/// Ctrl-\ Ctrl-N.
const vimNormal = '\x1c\x0e';

/// What to say and what it types.
class VimCommand {
  const VimCommand(this.label, this.keys, {this.confirm = false});

  /// Shown on the Voice status line.
  final String label;

  /// Typed after [vimNormal].
  final String keys;

  /// Throws work away: asks "yes" first.
  final bool confirm;
}

const vimOnPhrases = {'vim mode', 'vim mode on', 'vim on', 'v i m mode'};
const vimOffPhrases = {
  'vim mode off',
  'vim off',
  'exit vim mode',
  'leave vim mode',
};

const _fixed = <String, VimCommand>{
  'top': VimCommand('top of file', 'gg'),
  'go to top': VimCommand('top of file', 'gg'),
  'top of file': VimCommand('top of file', 'gg'),
  'top of the file': VimCommand('top of file', 'gg'),
  'beginning of file': VimCommand('top of file', 'gg'),
  'scroll to top': VimCommand('top of file', 'gg'),
  'jump to top': VimCommand('top of file', 'gg'),
  'bottom': VimCommand('end of file', 'G'),
  'go to bottom': VimCommand('end of file', 'G'),
  'end of file': VimCommand('end of file', 'G'),
  'end of the file': VimCommand('end of file', 'G'),
  'bottom of file': VimCommand('end of file', 'G'),
  'scroll to bottom': VimCommand('end of file', 'G'),
  'jump to bottom': VimCommand('end of file', 'G'),
  'beginning of line': VimCommand('beginning of line', '0'),
  'start of line': VimCommand('beginning of line', '0'),
  'beginning of the line': VimCommand('beginning of line', '0'),
  'start of the line': VimCommand('beginning of line', '0'),
  'first character': VimCommand('first character', '^'),
  'end of line': VimCommand('end of line', r'$'),
  'end of the line': VimCommand('end of line', r'$'),
  'next word': VimCommand('next word', 'w'),
  'word right': VimCommand('next word', 'w'),
  'forward a word': VimCommand('next word', 'w'),
  'previous word': VimCommand('previous word', 'b'),
  'word left': VimCommand('previous word', 'b'),
  'back a word': VimCommand('previous word', 'b'),
  'end of word': VimCommand('end of word', 'e'),
  'matching bracket': VimCommand('matching bracket', '%'),
  'matching paren': VimCommand('matching bracket', '%'),
  'matching parenthesis': VimCommand('matching bracket', '%'),
  'jump to matching': VimCommand('matching bracket', '%'),
  'center screen': VimCommand('center screen', 'zz'),
  'center line': VimCommand('center screen', 'zz'),
  'undo': VimCommand('undo', 'u'),
  'redo': VimCommand('redo', '\x12'),
  'insert': VimCommand('insert', 'i'),
  'insert mode': VimCommand('insert', 'i'),
  'append': VimCommand('append to line', 'A'),
  'append to line': VimCommand('append to line', 'A'),
  'new line below': VimCommand('new line below', 'o'),
  'new line above': VimCommand('new line above', 'O'),
  'delete line': VimCommand('delete line', 'dd'),
  'copy line': VimCommand('copy line', 'yy'),
  'paste': VimCommand('paste', 'p'),
  'paste above': VimCommand('paste above', 'P'),
  'find next': VimCommand('next match', 'n'),
  'next match': VimCommand('next match', 'n'),
  'find previous': VimCommand('previous match', 'N'),
  'previous match': VimCommand('previous match', 'N'),
  'save': VimCommand('save', ':w\r'),
  'save file': VimCommand('save', ':w\r'),
  'save and quit': VimCommand('save and quit', ':wq\r'),
  'save and exit': VimCommand('save and quit', ':wq\r'),
  'quit': VimCommand('quit', ':q\r'),
  'quit vim': VimCommand('quit', ':q\r'),
  'quit without saving': VimCommand(
    'quit without saving',
    ':q!\r',
    confirm: true,
  ),
  'force quit': VimCommand('quit without saving', ':q!\r', confirm: true),
};

final _line = RegExp(r'^(?:go to |jump to )?line (\d+)$');
final _lines = RegExp(
  r'^(down|up) (\d+)(?: lines?)?$|^(\d+) lines? (down|up)$',
);
final _search = RegExp(r'^(?:search for|search|find) (.+)$');

/// The vim command [spoken] (normalized) names, or null. "up" and "down"
/// alone stay the arrow keys; with a count they move that many lines.
/// [heard] is the utterance as the recognizer wrote it, for search text.
VimCommand? parseVimCommand(String spoken, String heard) {
  final fixed = _fixed[spoken];
  if (fixed != null) return fixed;
  final digits = numbersAsDigits(spoken);
  final line = _line.firstMatch(digits);
  if (line != null) return VimCommand('line ${line[1]}', '${line[1]}G');
  final lines = _lines.firstMatch(digits);
  if (lines != null) {
    final way = lines[1] ?? lines[4]!;
    final n = lines[2] ?? lines[3]!;
    return VimCommand('$way $n lines', '$n${way == 'down' ? 'j' : 'k'}');
  }
  final search = _search.firstMatch(spoken);
  if (search != null) {
    // The words as heard, not normalized: case and symbols are the search.
    final raw = heard.trim().replaceFirst(
      RegExp(r'^(search for|search|find)\s+', caseSensitive: false),
      '',
    );
    if (raw.isNotEmpty && !raw.contains('\n')) {
      return VimCommand('search $raw', '/$raw\r');
    }
  }
  return null;
}
