import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_macro.dart';

/// One literal find/replace substitution.
class MacroFindReplacePair {
  const MacroFindReplacePair({required this.find, required this.replace});

  final String find;
  final String replace;

  Map<String, dynamic> toJson() => {'find': find, 'replace': replace};

  factory MacroFindReplacePair.fromJson(Map<String, dynamic> json) {
    return MacroFindReplacePair(
      find: json['find']?.toString() ?? '',
      replace: json['replace']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MacroFindReplacePair &&
      other.find == find &&
      other.replace == replace;

  @override
  int get hashCode => Object.hash(find, replace);
}

/// Built-in model toggles. A model is named twice in authoring macros — the
/// display name in prose and the slug in `model=...` — so each toggle is a
/// pair of substitutions applied together.
const macroModelToggleToSol = <MacroFindReplacePair>[
  MacroFindReplacePair(find: 'Muse Wonder 1.0', replace: 'GPT-6.1 Sol'),
  MacroFindReplacePair(find: 'muse-wonder-1.0', replace: 'gpt-6.1-sol'),
];

const macroModelToggleToWonder = <MacroFindReplacePair>[
  MacroFindReplacePair(find: 'GPT-6.1 Sol', replace: 'Muse Wonder 1.0'),
  MacroFindReplacePair(find: 'gpt-6.1-sol', replace: 'muse-wonder-1.0'),
];

class MacroFindReplacePreset {
  const MacroFindReplacePreset({required this.label, required this.pairs});

  final String label;
  final List<MacroFindReplacePair> pairs;
}

const macroFindReplacePresets = <MacroFindReplacePreset>[
  MacroFindReplacePreset(
    label: 'Model → GPT-6.1 Sol',
    pairs: macroModelToggleToSol,
  ),
  MacroFindReplacePreset(
    label: 'Model → Muse Wonder 1.0',
    pairs: macroModelToggleToWonder,
  ),
];

class MacroFindReplaceOutcome {
  const MacroFindReplaceOutcome(this.text, this.replacements);

  final String text;
  final int replacements;
}

/// Applies literal [pairs] in order. An empty find is a no-op: it would
/// otherwise match everywhere and corrupt the text.
MacroFindReplaceOutcome applyMacroFindReplacePairs(
  String text,
  List<MacroFindReplacePair> pairs,
) {
  var result = text;
  var replacements = 0;
  for (final pair in pairs) {
    if (pair.find.isEmpty) continue;
    final count = pair.find.allMatches(result).length;
    if (count == 0) continue;
    replacements += count;
    result = result.replaceAll(pair.find, pair.replace);
  }
  return MacroFindReplaceOutcome(result, replacements);
}

class MacroFindReplaceMacrosOutcome {
  const MacroFindReplaceMacrosOutcome({
    required this.macros,
    required this.replacements,
    required this.affectedMacros,
  });

  final List<TerminalMacro> macros;
  final int replacements;
  final int affectedMacros;
}

/// Applies [pairs] to every step value of every macro.
MacroFindReplaceMacrosOutcome applyMacroFindReplaceToMacros(
  List<TerminalMacro> macros,
  List<MacroFindReplacePair> pairs,
) {
  var replacements = 0;
  var affected = 0;
  final updated = <TerminalMacro>[];
  for (final macro in macros) {
    var macroChanged = false;
    final steps = <TerminalMacroStep>[];
    for (final step in macro.steps) {
      final outcome = applyMacroFindReplacePairs(step.value, pairs);
      replacements += outcome.replacements;
      if (outcome.replacements > 0) macroChanged = true;
      steps.add(
        outcome.replacements > 0 ? step.copyWith(value: outcome.text) : step,
      );
    }
    if (macroChanged) affected++;
    updated.add(macroChanged ? macro.copyWith(steps: steps) : macro);
  }
  return MacroFindReplaceMacrosOutcome(
    macros: updated,
    replacements: replacements,
    affectedMacros: affected,
  );
}

/// Cached find/replace options, most recently used first. Persisted locally
/// so a swap the user performs once (for example a model toggle) is offered
/// again next time without retyping.
class MacroFindReplaceHistory {
  const MacroFindReplaceHistory(this.entries);

  static const empty = MacroFindReplaceHistory(<MacroFindReplacePair>[]);
  static const maxEntries = 12;

  final List<MacroFindReplacePair> entries;

  MacroFindReplaceHistory remember(MacroFindReplacePair pair) {
    if (pair.find.isEmpty) return this;
    final next = <MacroFindReplacePair>[
      pair,
      ...entries.where((entry) => entry != pair),
    ];
    return MacroFindReplaceHistory(
      next.length > maxEntries ? next.sublist(0, maxEntries) : next,
    );
  }

  String encode() =>
      jsonEncode(entries.map((entry) => entry.toJson()).toList());

  factory MacroFindReplaceHistory.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return MacroFindReplaceHistory.empty;
      final entries = decoded
          .whereType<Map>()
          .map(
            (entry) =>
                MacroFindReplacePair.fromJson(Map<String, dynamic>.from(entry)),
          )
          .where((entry) => entry.find.isNotEmpty)
          .take(maxEntries)
          .toList();
      return MacroFindReplaceHistory(entries);
    } catch (_) {
      return MacroFindReplaceHistory.empty;
    }
  }
}

const macroFindReplaceHistoryKey = 'macro_find_replace_history_v1';

Future<MacroFindReplaceHistory> loadMacroFindReplaceHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(macroFindReplaceHistoryKey);
  return raw == null
      ? MacroFindReplaceHistory.empty
      : MacroFindReplaceHistory.decode(raw);
}

Future<void> saveMacroFindReplaceHistory(
  MacroFindReplaceHistory history,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(macroFindReplaceHistoryKey, history.encode());
}

/// Shows the find & replace sheet and returns the pairs to apply, or null
/// when cancelled. Built-in model toggles and cached recent pairs are offered
/// as one-tap chips; whatever the user applies by hand is cached for next
/// time. [scopeLabel] names what will be changed, for example one macro or
/// every macro.
Future<List<MacroFindReplacePair>?> showMacroFindReplaceDialog(
  BuildContext context, {
  required String scopeLabel,
}) async {
  final history = await loadMacroFindReplaceHistory();
  if (!context.mounted) return null;
  final result = await showModalBottomSheet<List<MacroFindReplacePair>>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _MacroFindReplaceSheet(scopeLabel: scopeLabel, history: history),
  );
  if (result == null || result.isEmpty) return null;
  var next = history;
  for (final pair in result) {
    next = next.remember(pair);
  }
  await saveMacroFindReplaceHistory(next);
  return result;
}

class _MacroFindReplaceSheet extends StatefulWidget {
  const _MacroFindReplaceSheet({
    required this.scopeLabel,
    required this.history,
  });

  final String scopeLabel;
  final MacroFindReplaceHistory history;

  @override
  State<_MacroFindReplaceSheet> createState() => _MacroFindReplaceSheetState();
}

class _MacroFindReplaceSheetState extends State<_MacroFindReplaceSheet> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Find & replace', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Applies to ${widget.scopeLabel}. Matching is literal text.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in macroFindReplacePresets)
                  ActionChip(
                    avatar: const Icon(Icons.swap_horiz, size: 16),
                    label: Text(preset.label),
                    onPressed: () => Navigator.pop(context, preset.pairs),
                  ),
                for (final pair in widget.history.entries)
                  ActionChip(
                    label: Text(
                      '${pair.find} → ${pair.replace}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => Navigator.pop(context, [pair]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _findController,
              decoration: const InputDecoration(
                labelText: 'Find',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                labelText: 'Replace with',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final find = _findController.text;
                    if (find.isEmpty) {
                      Navigator.pop(context);
                      return;
                    }
                    Navigator.pop(context, [
                      MacroFindReplacePair(
                        find: find,
                        replace: _replaceController.text,
                      ),
                    ]);
                  },
                  child: const Text('Replace all'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
