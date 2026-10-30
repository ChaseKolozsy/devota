import 'dart:async';
import 'package:devota/serial_agent_writes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delayed earlier write cannot overwrite later typing', () async {
    final writes = SerialAgentWrites();
    final gate = Completer<void>();
    var stored = '';
    final first = writes.enqueue(() async {
      await gate.future;
      stored = 'ws://partial';
    });
    final second = writes.enqueue(() async {
      stored = 'ws://complete.test:8083/phone';
    });
    await Future<void>.delayed(Duration.zero);
    expect(stored, isEmpty);
    gate.complete();
    await Future.wait([first, second]);
    expect(stored, 'ws://complete.test:8083/phone');
  });
}
