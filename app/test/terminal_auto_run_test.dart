import 'dart:convert';
import 'package:devota/terminal_watch.dart';
import 'package:devota/terminal_macro.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  DateTime time = DateTime(2026);
  String screen = 'Starting.';
  String status = 'reported_success';
  String program = 'node';
  String reason = 'all 20 approved, 0 failed';
  final sent = <String>[];
  late final watch = TerminalWatchController(now: () => time);
  Fixture() {
    watch.configure(
      [
        TerminalWatchBinding(
          pane: const WatchedPane(
            id: '%1',
            identity: 'id1',
            label: 'Window 1',
            window: '1',
          ),
          macroId: 'm',
        ),
      ],
      [
        const TerminalMacro(
          id: 'm',
          name: 'Next batch',
          steps: [
            TerminalMacroStep(
              id: 's',
              type: TerminalMacroStepType.shell,
              value: 'go',
              delaySeconds: 0,
            ),
          ],
        ),
      ],
    );
    watch.connect(
      TmuxWatchTransport((command) async {
        if (command.contains('pane_current_command')) return '$program\n';
        if (command.contains('paste-buffer') ||
            command.contains('send-keys')) {
          sent.add(command);
        }
        return screen;
      }, reviewer: (source) async => jsonEncode({
        'status': status,
        'reason': reason,
        'evidence': source.split('\n').last,
      })),
    );
  }

  Future<void> tick([int seconds = 2]) async {
    time = time.add(Duration(seconds: seconds));
    await watch.poll();
    await Future<void>.delayed(Duration.zero);
  }

  /// Output appears at the current time, then stays quiet until reviewed.
  Future<void> finish(String report) async {
    screen = report;
    await tick(0);
    for (var i = 0; i < 6; i++) {
      await tick();
    }
  }

  Future<void> waitForRun() async {
    for (var i = 0; i < 50 && watch.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  String get status0 => watch.cards.single['status'] as String;
}

void main() {
  test('nothing runs until Start auto-run is tapped', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    expect(fixture.status0, startsWith('✓ Done · all 20'));
    expect(fixture.watch.cards.single['autoStart'], isTrue);
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    for (var i = 0; i < 20; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
  });

  test('Start on a Done window counts down, then runs once', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    await fixture.watch.startAutoRun('%1');
    expect(fixture.status0, startsWith('Auto-run in 10s · ✓ Done'));
    expect(fixture.watch.cards.single['autoStop'], isTrue);
    expect(fixture.watch.cards.single['autoStart'], isFalse);
    for (var i = 0; i < 4; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
    await fixture.tick();
    await fixture.tick();
    await fixture.waitForRun();
    expect(fixture.sent, isNotEmpty);
    final sends = fixture.sent.length;
    // The same screen never auto-runs twice, even if nothing changes.
    for (var i = 0; i < 20; i++) {
      await fixture.tick();
    }
    await fixture.waitForRun();
    expect(fixture.sent.length, sends);
    // Still armed: the next Done runs again.
    expect(fixture.watch.cards.single['autoStop'], isTrue);
    await fixture.finish('Done: all 20 approved. Failed: 0. Next batch.');
    expect(fixture.status0, startsWith('Auto-run in'));
  });

  test('a bare shell in the window stops automation, sends nothing', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    fixture.program = 'bash';
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    await fixture.watch.startAutoRun('%1');
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    expect(
      fixture.status0,
      startsWith('⚠ Auto-run not started: no agent running in this window (bash)'),
    );
    // Armed while the agent ran, then the agent exits before the countdown ends.
    fixture.program = 'codex';
    await fixture.watch.startAutoRun('%1');
    fixture.program = 'bash';
    for (var i = 0; i < 8; i++) {
      await fixture.tick();
    }
    await fixture.waitForRun();
    expect(fixture.sent, isEmpty);
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    expect(fixture.status0, startsWith('⚠ Auto-run stopped: no agent running'));
  });

  test('the shade toggle starts and stops every window', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    await fixture.watch.startAutoRunAll();
    expect(fixture.watch.cards.single['autoStop'], isTrue);
    expect(fixture.status0, startsWith('Auto-run in'));
    fixture.watch.stopAutoRunAll();
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    expect(fixture.watch.cards.single['autoStart'], isTrue);
    for (var i = 0; i < 10; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
  });

  test('Stop auto-run keeps the manual button', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    await fixture.watch.startAutoRun('%1');
    fixture.watch.stopAutoRun('%1');
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    expect(fixture.watch.cards.single['run'], isTrue);
    for (var i = 0; i < 20; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
  });

  test('a quiet window runs whatever the OCR verdict says', () async {
    for (final verdict in ['uncertain', 'needs_attention']) {
      final fixture = Fixture();
      fixture.status = verdict;
      await fixture.finish('Some output the OCR cannot judge');
      await fixture.watch.startAutoRun('%1');
      expect(fixture.status0, startsWith('Auto-run in 10s'), reason: verdict);
      for (var i = 0; i < 6; i++) {
        await fixture.tick();
      }
      await fixture.waitForRun();
      expect(fixture.sent, isNotEmpty, reason: verdict);
      fixture.watch.dispose();
    }
  });

  test('an empty queue stops automation instead of looping', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    fixture.status = 'needs_attention';
    fixture.reason = 'Queue empty';
    await fixture.finish('RESULT: EMPTY');
    await fixture.watch.startAutoRun('%1');
    for (var i = 0; i < 8; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
    expect(fixture.watch.cards.single['autoStop'], isFalse);
    expect(fixture.status0, startsWith('⚠ Auto-run stopped: queue empty'));
  });

  test('a disabled setting never auto-runs', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    fixture.watch.autoRunEnabled = false;
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    await fixture.watch.startAutoRun('%1');
    for (var i = 0; i < 20; i++) {
      await fixture.tick();
    }
    expect(fixture.sent, isEmpty);
  });

  test('new output cancels a pending auto-run', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    await fixture.tick(0);
    await fixture.watch.startAutoRun('%1');
    expect(fixture.watch.cards.single['autoStop'], isTrue);
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    fixture.screen = 'More output';
    await fixture.tick();
    expect(fixture.watch.observations['%1']!.autoRunAt, isNull);
    await fixture.tick(10);
    expect(fixture.sent, isEmpty);
  });

  test('timer, per-macro average and slower-than-usual warning', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    final recorded = <Map<String, List<int>>>[];
    fixture.watch.onDurationsChanged = recorded.add;
    fixture.watch.autoRunEnabled = false;
    fixture.status = 'uncertain';
    await fixture.finish('Idle');
    final token = fixture.watch.token(fixture.watch.bindings.single);
    await fixture.watch.act('%1', 'run', token);
    expect(fixture.status0, contains('⏱ 0s'));
    // Working for 10 minutes, then the report appears.
    fixture.screen = 'Working';
    await fixture.tick(600);
    expect(fixture.status0, contains('⏱ 10m'));
    fixture.status = 'reported_success';
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    expect(fixture.status0, startsWith('✓ Done in 10m (avg 10m) · '));
    expect(recorded.single, {
      'm': [600],
    });
    expect(fixture.watch.averageDuration('m'), const Duration(minutes: 10));

    // A second run well past the average leads with a warning.
    fixture.status = 'uncertain';
    await fixture.watch.act(
      '%1',
      'run',
      fixture.watch.token(fixture.watch.bindings.single),
    );
    fixture.screen = 'Working again';
    await fixture.tick(60 * 16);
    expect(fixture.status0, startsWith('⚠ 16m (avg 10m) · slower than usual'));
    fixture.status = 'reported_success';
    await fixture.finish('Done: all 20 approved. Failed: 0. Second.');
    expect(fixture.watch.macroDurations['m']!.length, 2);
    expect(fixture.watch.averageDuration('m')!.inMinutes, 13);
  });

  test('an unchanged report from before the run is not a new Done', () async {
    final fixture = Fixture();
    addTearDown(fixture.watch.dispose);
    fixture.watch.autoRunEnabled = false;
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    expect(fixture.status0, startsWith('✓ Done'));
    await fixture.watch.act(
      '%1',
      'run',
      fixture.watch.token(fixture.watch.bindings.single),
    );
    fixture.screen = 'busy';
    await fixture.tick();
    await fixture.finish('Done: all 20 approved. Failed: 0.');
    expect(fixture.status0, contains('Earlier report still showing'));
  });

  test('formatRunTime', () {
    expect(formatRunTime(const Duration(seconds: 42)), '42s');
    expect(formatRunTime(const Duration(minutes: 18, seconds: 5)), '18m');
    expect(formatRunTime(const Duration(hours: 1, minutes: 5)), '1h05m');
  });
}
