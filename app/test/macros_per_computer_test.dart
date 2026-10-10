import 'dart:convert';

import 'package:devota/main.dart';
import 'package:devota/ssh_terminal_tab.dart';
import 'package:devota/terminal_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _macro(String lang) => {
  'id': 'author',
  'name': 'Author $lang',
  'steps': [
    {
      'id': 's',
      'type': 'shell',
      'value': '{{devota:queue:$lang:forward}}',
    },
  ],
};

void main() {
  testWidgets('switching computers swaps the macro list and keeps both', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('io.github.chasekolozsy.devota/control_agent');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getAgentStatus'
          ? {'running': false, 'connected': false}
          : true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const main = TerminalProfile(
      id: 'main',
      name: 'Main',
      host: 'main',
      username: 'chase',
      serverUrl: 'http://main.invalid:8082',
    );
    const palm = TerminalProfile(
      id: 'palm',
      name: 'Palm',
      host: 'palm',
      username: 'chase',
      serverUrl: 'http://palm.invalid:8084',
    );
    SharedPreferences.setMockInitialValues({
      TerminalProfiles.profilesKey: jsonEncode([main.toJson(), palm.toJson()]),
      TerminalProfiles.selectedKey: main.id,
      TerminalProfiles.unifiedKey: true,
      // Saved before lists were per computer: it is the selected computer's.
      'macros_json': jsonEncode([_macro('alpha')]),
      'macros_by_profile_json': jsonEncode({
        'palm': {
          'macros': [_macro('beta')],
          'usageCounts': {},
        },
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const DevOtaApp());
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    Future<void> tab(int i) async {
      tester
          .widget<TabBar>(find.byType(TabBar).first)
          .controller!
          .animateTo(i);
      await tester.pumpAndSettle();
    }

    Future<void> select(String name) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await tab(5);
    expect(find.text('Author alpha'), findsOneWidget);
    await tab(3); // Open Main's terminal so it is retained.
    await tab(0);
    await select('Palm');
    await tab(5);
    expect(find.text('Author beta'), findsOneWidget);
    expect(find.text('Author alpha'), findsNothing);

    // Main's terminal, retained behind Palm's, still holds Main's macros.
    await tab(3);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('macros_json')!)[0]['name'], 'Author beta');
    expect(prefs.getString('macros_profile_id'), 'palm');
    final byProfile = jsonDecode(prefs.getString('macros_by_profile_json')!);
    expect(byProfile['main']['macros'][0]['name'], 'Author alpha');
    expect(byProfile['palm']['macros'][0]['name'], 'Author beta');
    final terminals = tester.widgetList<SshTerminalTab>(
      find.byType(SshTerminalTab, skipOffstage: false),
    );
    expect(terminals, hasLength(2));
    for (final terminal in terminals) {
      final lang = terminal.profileId == 'main' ? 'alpha' : 'beta';
      expect(terminal.notificationMacros.single.name, 'Author $lang');
    }

    await tab(0);
    await select('Main');
    await tab(5);
    expect(find.text('Author alpha'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
