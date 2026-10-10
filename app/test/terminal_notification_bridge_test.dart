import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devota/terminal_notification_bridge.dart';
import 'package:devota/terminal_watch.dart';

void main() {
  const channel = MethodChannel('devota/terminal_notifications');
  testWidgets('session notification actions are forwarded to the terminal', (
    tester,
  ) async {
    String? received;
    final watch = TerminalWatchController();
    final bridge = TerminalNotificationBridge(
      watch,
      onSessionAction: (action) async => received = action,
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('sessionAction', {'action': 'restartZeroTier'}),
      ),
      (_) {},
    );
    await tester.pump();
    expect(received, 'restartZeroTier');
    bridge.dispose();
    watch.dispose();
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('publication bursts coalesce and delivery is acknowledged', (
    tester,
  ) async {
    var updates = 0;
    final watch = TerminalWatchController();
    final bridge = TerminalNotificationBridge(watch);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'update') updates++;
      if (call.method == 'status') {
        return {'allowed': true, 'posted': 3, 'requested': 3};
      }
      return null;
    });
    for (var i = 0; i < 50; i++) {
      bridge.publish();
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 350));
    expect(updates, 1);
    expect(
      bridge.deliveryStatus.value,
      'Android reports 3/3 window cards posted.',
    );
    bridge.dispose();
    // A late disconnect callback must not schedule work after disposal.
    bridge.publish();
    watch.dispose();
    await tester.pump(const Duration(milliseconds: 350));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets('Save cannot confirm delivery while the bridge is disabled', (
    tester,
  ) async {
    final watch = TerminalWatchController();
    watch.configure([
      TerminalWatchBinding(
        pane: const WatchedPane(
          id: '%0',
          identity: 'id',
          label: 'test:1.0',
          window: '1',
        ),
        macroId: 'test',
      ),
    ], []);
    final bridge = TerminalNotificationBridge(watch)..enabled = false;
    await expectLater(bridge.verifyDelivery(), throwsStateError);
    bridge.dispose();
    watch.dispose();
    await tester.pump(const Duration(milliseconds: 350));
  });

  for (final blocked in [false, true]) {
    testWidgets(
      'Save exposes ${blocked ? 'blocked channel' : 'missing cards'}',
      (tester) async {
        final watch = TerminalWatchController();
        watch.configure([
          TerminalWatchBinding(
            pane: const WatchedPane(
              id: '%0',
              identity: 'id',
              label: 'test:1.0',
              window: '1',
            ),
            macroId: 'test',
          ),
        ], []);
        final bridge = TerminalNotificationBridge(watch);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'status') {
              return {'allowed': !blocked, 'posted': 0, 'requested': 1};
            }
            return null;
          },
        );
        final result = expectLater(bridge.verifyDelivery(), throwsStateError);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        if (!blocked) {
          await tester.pump(const Duration(seconds: 2));
          await tester.pump(const Duration(milliseconds: 350));
        }
        await result;
        expect(
          bridge.deliveryStatus.value,
          contains(blocked ? 'blocked' : '0/1'),
        );
        bridge.dispose();
        watch.dispose();
        await tester.pump(const Duration(milliseconds: 350));
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      },
    );
  }
  testWidgets(
    'inactive session disposal preserves the selected notification handler',
    (tester) async {
      final firstWatch = TerminalWatchController();
      final secondWatch = TerminalWatchController();
      String? recipient;
      final first = TerminalNotificationBridge(
        firstWatch,
        onSessionAction: (_) async => recipient = 'first',
      );
      first.setActive(false);
      final second = TerminalNotificationBridge(
        secondWatch,
        onSessionAction: (_) async => recipient = 'second',
      );
      first.dispose();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('sessionAction', {'action': 'disconnect'}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(recipient, 'second');
      second.dispose();
      firstWatch.dispose();
      secondWatch.dispose();
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets(
    'two computers publish their cards together and actions reach the right one',
    (tester) async {
      TerminalWatchController watched(String label) =>
          TerminalWatchController()..configure([
            TerminalWatchBinding(
              pane: WatchedPane(
                id: '%0',
                identity: label,
                label: label,
                window: '1',
              ),
              macroId: 'author',
            ),
          ], []);
      final mainWatch = watched('main:1.0');
      final palmWatch = watched('palm:1.0');
      List<Map<Object?, Object?>> published = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'update') {
          published = (call.arguments['cards'] as List)
              .cast<Map<Object?, Object?>>();
        }
        return null;
      });
      final palm = TerminalNotificationBridge(palmWatch, label: () => 'Palm');
      final main = TerminalNotificationBridge(mainWatch, label: () => 'Main');
      // Palm keeps authoring in the background while Main is on screen.
      palm.setActive(false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(published.map((card) => card['id']), ['%0~1', '%0']);
      expect(published.map((card) => card['title']), [
        'Main · main:1.0',
        'Palm · palm:1.0',
      ]);

      // Palm's pane %0 is a different window from Main's pane %0.
      palmWatch.observations['%0'] = PaneObservation();
      mainWatch.observations['%0'] = PaneObservation();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('actionRejected', {'id': '%0'}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(palmWatch.observations['%0']!.runError, isNotNull);
      expect(mainWatch.observations['%0']!.runError, isNull);

      // Closing one computer's terminal leaves the other's cards up.
      palm.dispose();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 350));
      expect(published.map((card) => card['id']), ['%0~1']);
      expect(published.single['title'], 'main:1.0');
      main.dispose();
      await tester.pump(const Duration(milliseconds: 350));
      expect(published, isEmpty);
      mainWatch.dispose();
      palmWatch.dispose();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
