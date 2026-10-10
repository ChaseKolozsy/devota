import 'dart:convert';

import 'package:devota/ssh_terminal_tab.dart';
import 'package:devota/terminal_pad_key.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With the tools collapsed, the Tools bar carries its own buttons: Backspace
/// and Enter unless the user picks others, two visible, the rest a swipe away.
void main() {
  late List<String> writes;

  Map<String, Object> prefs({List<String>? collapsedIds}) => {
    'terminal_tools_visible': false,
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
      'collapsedIds': ?collapsedIds,
    }),
  };

  setUp(() => writes = []);

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

  testWidgets('a saved layout from before gets Backspace and Enter', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(prefs());
    await pumpTab(tester);
    expect(find.text('Tap to show terminal controls'), findsNothing);
    expect(key('Backspace'), findsOneWidget, reason: 'the pad is hidden');
    expect(key('Enter'), findsOneWidget);

    await tester.tap(key('Backspace'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(key('Enter'));
    await tester.pump(const Duration(seconds: 1));
    expect(writes, ['\x7F', '\r']);
    expect(key('Tab'), findsNothing, reason: 'tapping a key does not expand');
  });

  testWidgets('holding the bar Backspace keeps deleting', (tester) async {
    SharedPreferences.setMockInitialValues(prefs());
    await pumpTab(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(key('Backspace')),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(writes.length, greaterThan(10));
    expect(writes.toSet(), {'\x7F'});
  });

  testWidgets('more than two buttons scroll, two at a time', (tester) async {
    SharedPreferences.setMockInitialValues(
      prefs(collapsedIds: ['tab', 'esc', 'home', 'end', 'enter']),
    );
    await pumpTab(tester);
    final window = tester.getRect(
      find.byKey(const ValueKey('collapsed-tools-keys')),
    );
    expect(window.width, lessThan(140));
    bool shown(String name) {
      final f = key(name);
      if (f.evaluate().isEmpty) return false;
      final r = tester.getRect(f.first);
      return r.left >= window.left - 1 && r.right <= window.right + 1;
    }

    expect(shown('Tab'), isTrue);
    expect(shown('Escape'), isTrue);
    expect(shown('Enter'), isFalse);

    await tester.drag(
      find.byKey(const ValueKey('collapsed-tools-keys')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(shown('Enter'), isTrue);
    expect(shown('Tab'), isFalse);
    await tester.tap(key('Enter'));
    await tester.pump(const Duration(seconds: 1));
    expect(writes, ['\r']);
  });

  testWidgets('no buttons chosen leaves the hint', (tester) async {
    SharedPreferences.setMockInitialValues(prefs(collapsedIds: []));
    await pumpTab(tester);
    expect(find.text('Tap to show terminal controls'), findsOneWidget);
    expect(key('Backspace'), findsNothing);
  });

  test('the collapsed list round-trips and defaults', () {
    final fresh = TerminalPadConfig.defaults();
    expect(fresh.collapsedIds, ['backspace', 'enter']);
    final old = TerminalPadConfig.decode(jsonEncode({'rows': []}));
    expect(old.collapsedIds, ['backspace', 'enter']);
    fresh.collapsedIds = ['esc'];
    expect(TerminalPadConfig.decode(fresh.encode()).collapsedIds, ['esc']);
    fresh.collapsedIds = [];
    expect(TerminalPadConfig.decode(fresh.encode()).collapsedIds, isEmpty);
  });
}
