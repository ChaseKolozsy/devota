import 'dart:convert';

import 'package:devota/ssh_terminal_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves `GET /terminal/compose` once with [first] and `GET /terminal/speak`
/// once with [speech], then empty.
class _ComposeServer implements HttpClientAdapter {
  _ComposeServer(this.first, {this.speech = const []});

  final List<Map<String, Object>> first;
  final List<Map<String, Object>> speech;
  final paths = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    paths.add(path);
    final firstAsk = paths.where((p) => p == path).length == 1;
    final items = !firstAsk
        ? const <Map<String, Object>>[]
        : path == '/terminal/speak'
        ? speech
        : first;
    return ResponseBody.fromString(
      jsonEncode({'status': 'ok', 'items': items}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  testWidgets('a proposed command fills the text box and is not sent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final server = _ComposeServer([
      {'id': 1, 'text': 'echo older', 'label': 'Claude'},
      {'id': 2, 'text': 'gh auth status', 'label': 'Claude'},
    ]);
    final dio = Dio()..httpClientAdapter = server;
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SshTerminalTab(
            dio: dio,
            serverUrl: 'http://devota.test:8082/',
            testHooks: SshTerminalTestHooks(sessionSink: sent.add),
          ),
        ),
      ),
    );
    await tester.pump();
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Type command',
    );
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(server.paths, ['/terminal/compose', '/terminal/speak']);
    expect(tester.widget<TextField>(field).controller!.text, 'gh auth status');
    expect(find.textContaining('Command ready in the'), findsOneWidget);
    expect(sent, isEmpty);

    // Handed over once: the next check leaves the box as the person left it.
    tester.widget<TextField>(field).controller!.text = 'edited by hand';
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(server.paths, hasLength(4));
    expect(tester.widget<TextField>(field).controller!.text, 'edited by hand');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('an agent message is said aloud, never typed or sent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    const speech = MethodChannel('devota/terminal_notifications');
    final spoken = <Map>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(speech, (
      call,
    ) async {
      if (call.method == 'speak') spoken.add(call.arguments as Map);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        speech,
        null,
      ),
    );
    final server = _ComposeServer(
      const [],
      speech: [
        {'id': 1, 'text': '**Tests pass.**', 'label': 'Claude'},
        {'id': 2, 'text': 'Shall I push?', 'label': 'Claude'},
      ],
    );
    final dio = Dio()..httpClientAdapter = server;
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SshTerminalTab(
            dio: dio,
            serverUrl: 'http://devota.test:8082/',
            testHooks: SshTerminalTestHooks(sessionSink: sent.add),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(spoken, hasLength(1), reason: 'both messages, read once');
    expect(spoken.single['text'], 'Claude says: Tests pass. Shall I push?');
    expect(spoken.single['title'], startsWith('Claude'));
    expect(find.textContaining('Claude: Tests pass.'), findsOneWidget);
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Type command',
    );
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(sent, isEmpty);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(spoken, hasLength(1), reason: 'handed over once');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
