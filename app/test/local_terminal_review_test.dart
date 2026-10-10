import 'dart:convert';
import 'dart:io';
import 'package:devota/local_terminal_review.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local rules preserve failures, negation, partial counts and new prompts',
    () {
      for (final source in [
        'All work complete. Tests failed.',
        'Not complete. Changes committed and pushed.',
        '19/20 completed and approved.',
        'All work complete. Please confirm the install.',
      ]) {
        expect(
          classifyTerminalText(source).status,
          'needs_attention',
          reason: source,
        );
      }
      for (final source in [
        'All work complete.\n❯ Start the next task\n● Working on it',
        'I will fix this. Changes committed and pushed.',
        '42 tests passed.',
        'Done.',
        'If all work complete, report success.',
        'All work complete, but verification remains pending.',
      ]) {
        expect(
          classifyTerminalText(source).status,
          isNot('reported_success'),
          reason: source,
        );
      }
      expect(
        classifyTerminalText('All work complete.').status,
        'reported_success',
      );
      expect(
        classifyTerminalText('Implemented and verified the changes.').status,
        'reported_success',
      );
    },
  );
  test('authoring reports: zero failures are clean, counts are checked', () {
    for (final source in [
      'Done: all 20 articles compiled, were created, '
          'reviewed, and approved. Corrected one sentence in dalaga before '
          'approval.\n\n20 approved · 0 skipped · 0 failed.',
      'Done: 20 articles authored, compiled clean, '
          'reviewed, and approved. Skipped: 0. Failed: 0.',
      'Done: all 20 glossary entries were drafted, compiled, '
          'reviewed, and approved. No topics were skipped or left unresolved.',
      'Done. All 20 tutorial lessons were created, '
          'reviewed, and approved. The haza submission rejection was '
          'repaired; no topics remain unresolved.',
      'Done: 20 articles drafted, compiled cleanly, '
          'reviewed, created, and approved. 0 skipped; 0 unresolved '
          'failures. A temporary connection failure was recovered.',
      'All 20 submitted\nZero failures',
      '20/20 approved, all submitted.',
      // Wrapped by the terminal mid-phrase.
      'Done: all 20 articles were drafted, compiled\n'
          '  clean, reviewed, and approved. Skipped: 0. Failed: 0.',
    ]) {
      expect(
        classifyTerminalText(source).status,
        'reported_success',
        reason: source,
      );
    }
    for (final source in [
      'Done: 18/20 approved. Skipped: 0. Failed: 2.',
      'Done: all 20 drafted; 2 failed compilation.',
      'Done — the assigned roster is empty.',
      'Done: 19 of 20 lessons approved.',
      'Two lessons failed and could not be recovered.',
      'Approved 20 lessons. Should I start the next batch?',
      'Please identify the intended release app.',
    ]) {
      expect(
        classifyTerminalText(source).status,
        'needs_attention',
        reason: source,
      );
    }
    for (final source in [
      'I’m using the project authoring skill for this batch.',
      'All 20 lessons staged successfully. I’ll save and reread those '
          'corrections before approval.',
      'Working (3m 56s • esc to interrupt)',
      'Ready for a new task.',
    ]) {
      expect(
        classifyTerminalText(source).status,
        'uncertain',
        reason: source,
      );
    }
    final verdict = classifyTerminalText(
      'Done: all 20 approved. Skipped: 0. Failed: 0.',
    );
    expect(verdict.reason, 'all 20 approved, 0 failed');
  });
  test('RESULT line from the macro prompt wins', () {
    final done = classifyTerminalText(
      'Fixed two wording issues before approval.\n'
      'RESULT: DONE 20/20 approved, 0 failed, 0 skipped',
    );
    expect(done.status, 'reported_success');
    expect(done.reason, '20/20 approved, 0 failed, 0 skipped');
    expect(done.evidence, 'RESULT: DONE 20/20 approved, 0 failed, 0 skipped');
    for (final line in [
      'RESULT: DONE 18/20 approved, 2 failed, 0 skipped',
      'RESULT: CHECK 20/20 approved, 0 failed, 0 skipped',
      'RESULT: EMPTY',
    ]) {
      expect(classifyTerminalText(line).status, 'needs_attention', reason: line);
    }
    // A template with placeholders echoed from a prompt is not a report.
    expect(
      classifyTerminalText(
        'RESULT: DONE <approved>/<assigned> approved, <failed> failed',
      ).status,
      'uncertain',
    );
  });
  test('agent input boxes and footers are not new requests', () {
    const codex =
        '• Done: all 20 articles were drafted, compiled,\n'
        '  reviewed, and approved. Skipped: 0. Failed: 0.\n'
        '\n'
        '› Ask Codex to do anything\n'
        '  GPT-6.1-Sol medium · ~ · Run article batch · Main\n'
        '  ← for agents · ? for shortcuts\n';
    expect(
      classifyTerminalText(terminalReviewExcerpt(codex)).status,
      'reported_success',
    );
    const claude =
        '● Committed and pushed to main.\n'
        '\n'
        '──────────────────\n'
        '❯ \n'
        '──────────────────\n'
        '  ⏵⏵ bypass permissions on (shift+tab to cycle)\n';
    expect(
      classifyTerminalText(terminalReviewExcerpt(claude)).status,
      'reported_success',
    );
    // A submitted prompt echoed under an old report means a new turn.
    const resent =
        '● Committed and pushed to main.\n'
        '> Use the authoring skill. End with RESULT: DONE 20/20 approved\n'
        '──────────────────\n'
        '❯ \n'
        '──────────────────\n';
    expect(
      classifyTerminalText(terminalReviewExcerpt(resent)).status,
      'uncertain',
    );
    // Codex progress bullets before the final reply are superseded.
    const progress =
        '• Explored\n  └ Read SKILL.md\n'
        '• All 20 lessons staged. I’ll reread corrections before approval.\n'
        '• Done: all 20 approved. Skipped: 0. Failed: 0.\n'
        '› Ask Codex to do anything\n';
    expect(
      classifyTerminalText(terminalReviewExcerpt(progress)).status,
      'reported_success',
    );
  });
  test('recorded agent reports: no false Done on problem reports', () {
    final reports =
        (jsonDecode(
                  File('test/fixtures/agent_reports.json').readAsStringSync(),
                )
                as List)
            .cast<String>();
    var done = 0;
    for (final report in reports) {
      final verdict = classifyTerminalText(report);
      if (verdict.status != 'reported_success') continue;
      done++;
      expect(
        RegExp(
          r'roster is empty|I’ll|\b[1-9]\d* (?:failed|skipped)\b',
        ).hasMatch(report),
        isFalse,
        reason: report,
      );
    }
    // End-of-batch report phrasings modelled on real agent runs: every clean
    // report reads as Done, and none of the last six (problem reports) does.
    expect(done, reports.length - 6);
  });
  test('snapshot isolates newest reply and is bounded', () {
    final excerpt = terminalReviewExcerpt(
      '● All work complete.\n❯ New request\n'
      '● Tests failed.\n❯\n',
    );
    expect(excerpt, isNot(contains('All work complete')));
    expect(classifyTerminalText(excerpt).status, 'needs_attention');
    final bounded = terminalReviewExcerpt(
      List.filled(100, 'x' * 300).join('\n'),
    );
    expect(bounded.length, lessThanOrEqualTo(6000));
    expect(bounded.split('\n').length, lessThanOrEqualTo(40));
  });
  test(
    'OCR cannot erase failure to turn a report green; no host model call',
    () async {
      const channel = MethodChannel('devota/terminal_review');
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'recognizeSnapshot');
            calls++;
            return 'All work complete.';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bad = jsonDecode(
        await reviewTerminalLocally('All work complete. Tests failed.'),
      );
      expect(bad['status'], 'uncertain');
      final good = jsonDecode(
        await reviewTerminalLocally('All work complete.'),
      );
      expect(good['status'], 'reported_success');
      expect(good['evidence'], 'All work complete.');
      expect(calls, 2);
    },
  );
}
