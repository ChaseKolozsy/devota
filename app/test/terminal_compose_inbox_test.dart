import 'dart:convert';
import 'dart:typed_data';

import 'package:devota/ssh_terminal_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves `GET /terminal/compose` once with [first], then empty.
class _ComposeServer implements HttpClientAdapter {
  _ComposeServer(this.first);

  final List<Map<String, Object>> first;
  final paths = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    final items = paths.length == 1 ? first : const <Map<String, Object>>[];
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
    expect(server.paths, ['/terminal/compose']);
    expect(tester.widget<TextField>(field).controller!.text, 'gh auth status');
    expect(find.textContaining('Command ready in the'), findsOneWidget);
    expect(sent, isEmpty);

    // Handed over once: the next check leaves the box as the person left it.
    tester.widget<TextField>(field).controller!.text = 'edited by hand';
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(server.paths, hasLength(2));
    expect(tester.widget<TextField>(field).controller!.text, 'edited by hand');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
