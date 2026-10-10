import 'dart:convert';

import 'package:devota/ssh_terminal_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backspace repeats while held, and the row-end keys are wide, not tall.
void main() {
  late List<String> writes;

  setUp(() {
    writes = [];
    SharedPreferences.setMockInitialValues({
      'terminal_pad_config_json': jsonEncode({
        'version': 1,
        'customKeys': [],
        'rows': [
          {
            'middleIds': ['tab', 'esc'],
            'fixedRightId': 'backspace',
          },
          {
            'middleIds': ['home', 'end'],
            'fixedRightId': 'enter',
          },
        ],
      }),
    });
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 800,
            child: SshTerminalTab(
              dio: Dio(),
              serverUrl: 'http://127.0.0.1:8082',
              testHooks: SshTerminalTestHooks(sessionSink: writes.add),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder key(String name) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == name,
  );

  testWidgets('a tap on backspace deletes one character', (tester) async {
    await pumpTab(tester);
    await tester.tap(key('Backspace'));
    await tester.pump(const Duration(seconds: 1));
    expect(writes, ['\x7F']);
  });

  testWidgets('holding backspace keeps deleting until the finger lifts', (
    tester,
  ) async {
    await pumpTab(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(key('Backspace')),
    );
    await tester.pump(const Duration(milliseconds: 550));
    expect(writes, ['\x7F'], reason: 'the hold sends the first one');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final held = writes.length;
    expect(held, greaterThan(15));
    expect(writes.toSet(), {'\x7F'});
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(writes.length, held, reason: 'lifting stops the repeat');
  });

  testWidgets('holding Enter sends it once', (tester) async {
    await pumpTab(tester);
    final gesture = await tester.startGesture(tester.getCenter(key('Enter')));
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(writes.length, lessThanOrEqualTo(1));
    expect(writes.where((w) => w != '\r'), isEmpty);
  });

  testWidgets('backspace and Enter are wide, not tall', (tester) async {
    await pumpTab(tester);
    for (final name in ['Backspace', 'Enter']) {
      final size = tester.getSize(key(name));
      expect(size.width, greaterThanOrEqualTo(60), reason: name);
      expect(size.height, lessThanOrEqualTo(32), reason: name);
    }
    expect(tester.takeException(), isNull);
  });
}
