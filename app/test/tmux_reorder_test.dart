import 'dart:convert';

import 'package:devota/ssh_terminal_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpTerminal(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 700,
          child: SshTerminalTab(dio: Dio(), serverUrl: ''),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _left(WidgetTester tester, String label) =>
    tester.getTopLeft(find.widgetWithText(OutlinedButton, label)).dx;

void main() {
  testWidgets('the tmux row follows a saved arrangement', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'terminal_tmux_order_json': jsonEncode(['tmux_detach', 'tmux_next']),
    });
    await _pumpTerminal(tester);

    // Arranged buttons lead in the saved order; the rest keep catalog order.
    expect(_left(tester, 'Detach'), lessThan(_left(tester, 'Next')));
    expect(_left(tester, 'Next'), lessThan(_left(tester, 'New')));
    expect(_left(tester, 'New'), lessThan(_left(tester, 'Prev')));
    expect(_left(tester, 'Prev'), lessThan(_left(tester, '0')));
  });

  testWidgets('the default row is New, Next, Prev, windows 0-5, then the rest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      // Heavy use of Prefix no longer pulls it ahead of the window buttons.
      'terminal_key_usage_counts_json': jsonEncode({'tmux_prefix': 50}),
    });
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 700,
            child: SshTerminalTab(
              dio: Dio(),
              serverUrl: '',
              testHooks: SshTerminalTestHooks(sessionSink: sent.add),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final order = ['New', 'Next', 'Prev', '0', '1', '2', '3', '4', '5', 'Prefix'];
    for (var i = 1; i < order.length; i++) {
      expect(_left(tester, order[i - 1]), lessThan(_left(tester, order[i])));
    }
    await tester.tap(find.widgetWithText(OutlinedButton, '3'));
    await tester.pump();
    expect(sent.join(), contains('\x023'));
  });

  testWidgets('holding a tmux button and dragging it moves it and is kept', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await _pumpTerminal(tester);
    expect(_left(tester, 'Prefix'), lessThan(_left(tester, 'List')));

    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(OutlinedButton, 'List')),
    );
    var elapsed = kLongPressTimeout + const Duration(milliseconds: 20);
    await tester.pump(elapsed);
    // Slowly, so the drop lands where the finger stops (no flick).
    final target = tester.getCenter(find.widgetWithText(OutlinedButton, 'Prefix'));
    final start = tester.getCenter(find.widgetWithText(OutlinedButton, 'List'));
    const steps = 20;
    final step = Offset((target.dx - start.dx - 20) / steps, 0);
    for (var i = 0; i < steps; i++) {
      elapsed += const Duration(milliseconds: 60);
      await gesture.moveBy(step, timeStamp: elapsed);
      await tester.pump(const Duration(milliseconds: 60));
    }
    elapsed += const Duration(milliseconds: 300);
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up(timeStamp: elapsed);
    await tester.pumpAndSettle();

    expect(_left(tester, 'List'), lessThan(_left(tester, 'Prefix')));
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('terminal_tmux_order_json')!);
    final ids = (saved as List).cast<String>();
    expect(ids.indexOf('tmux_list'), ids.indexOf('tmux_prefix') - 1);

    // A fresh terminal shows the same arrangement.
    await tester.pumpWidget(const SizedBox());
    await _pumpTerminal(tester);
    expect(_left(tester, 'List'), lessThan(_left(tester, 'Prefix')));
  });
}
