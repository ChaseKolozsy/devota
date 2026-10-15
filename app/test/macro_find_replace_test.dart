import 'package:devota/macro_find_replace.dart';
import 'package:devota/terminal_macro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TerminalMacro _macro(String id, String value) {
  return TerminalMacro(
    id: id,
    name: id,
    steps: [
      TerminalMacroStep(
        id: '$id-step',
        type: TerminalMacroStepType.shell,
        value: value,
        delaySeconds: 0,
      ),
    ],
  );
}

void main() {
  test('model toggle pairs switch display name and slug both ways', () {
    const wonder =
        'The parent runs Muse Wonder 1.0 MEDIUM. '
        'Dispatch drafters (model=muse-wonder-1.0, reasoning_effort=medium)';
    final toSol = applyMacroFindReplacePairs(wonder, macroModelToggleToSol);
    expect(toSol.replacements, 2);
    expect(
      toSol.text,
      'The parent runs GPT-6.1 Sol MEDIUM. '
      'Dispatch drafters (model=gpt-6.1-sol, reasoning_effort=medium)',
    );

    final back = applyMacroFindReplacePairs(
      toSol.text,
      macroModelToggleToWonder,
    );
    expect(back.replacements, 2);
    expect(back.text, wonder);
  });

  test('applying to macros counts replacements and affected macros', () {
    final macros = [
      _macro('a', 'use muse-wonder-1.0 here'),
      _macro('b', 'nothing to change'),
      _macro('c', 'muse-wonder-1.0 and muse-wonder-1.0'),
    ];
    final result = applyMacroFindReplaceToMacros(macros, macroModelToggleToSol);
    expect(result.replacements, 3);
    expect(result.affectedMacros, 2);
    expect(result.macros[1].steps.single.value, 'nothing to change');
    expect(result.macros[2].steps.single.value, 'gpt-6.1-sol and gpt-6.1-sol');
  });

  test('empty find is a no-op', () {
    final result = applyMacroFindReplacePairs('abc', const [
      MacroFindReplacePair(find: '', replace: 'x'),
    ]);
    expect(result.replacements, 0);
    expect(result.text, 'abc');
  });

  test('history is most-recent-first, deduped, capped, and round-trips', () {
    var history = MacroFindReplaceHistory.empty;
    for (var i = 0; i < 15; i++) {
      history = history.remember(
        MacroFindReplacePair(find: 'f$i', replace: 'r$i'),
      );
    }
    history = history.remember(
      const MacroFindReplacePair(find: 'f14', replace: 'r14'),
    );
    expect(history.entries, hasLength(MacroFindReplaceHistory.maxEntries));
    expect(history.entries.first.find, 'f14');
    final restored = MacroFindReplaceHistory.decode(history.encode());
    expect(restored.entries, history.entries);
  });

  test('history persists through SharedPreferences cache', () async {
    SharedPreferences.setMockInitialValues({});
    await saveMacroFindReplaceHistory(
      MacroFindReplaceHistory.empty.remember(
        const MacroFindReplacePair(
          find: 'muse-wonder-1.0',
          replace: 'gpt-6.1-sol',
        ),
      ),
    );
    final loaded = await loadMacroFindReplaceHistory();
    expect(loaded.entries.single.find, 'muse-wonder-1.0');
    expect(loaded.entries.single.replace, 'gpt-6.1-sol');
  });
}
