import 'package:devota/ssh_terminal_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('one tap clears the text box, with the phone keyboard off', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'terminal_native_keyboard_locked': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SshTerminalTab(
            dio: Dio(),
            serverUrl: '',
            testHooks: SshTerminalTestHooks(sessionSink: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Type command',
    );
    expect(tester.widget<TextField>(field).readOnly, isTrue);
    expect(find.byTooltip('Clear text'), findsNothing);
    tester.widget<TextField>(field).controller!.text = 'a long dictated line';
    await tester.pump();
    await tester.tap(find.byTooltip('Clear text'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.byTooltip('Clear text'), findsNothing);
  });

  testWidgets('the terminal header fits a phone screen (buttons scroll)', (
    tester,
  ) async {
    // A REVVL 5G: 720 px wide at 2x.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SshTerminalTab(
            dio: Dio(),
            serverUrl: '',
            fullscreen: true,
            onFullscreenChanged: (_) {},
            testHooks: SshTerminalTestHooks(sessionSink: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('SSH settings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sign in from this phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
