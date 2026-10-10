import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'terminal_watch.dart';
import 'terminal_conclusion.dart';

class TerminalNotificationBridge {
  TerminalNotificationBridge(
    this.watch, {
    this.onSessionAction,
    this.label,
    bool active = true,
  }) : slot = _freeSlot() {
    _bridges.add(this);
    setActive(active);
    watch.addListener(publish);
  }

  /// Every live terminal's bridge. Android has one set of window cards, so the
  /// cards of every connected computer are published together: a computer
  /// left authoring in the background keeps its cards and auto-run controls
  /// while another is on screen.
  static final _bridges = <TerminalNotificationBridge>[];
  static TerminalNotificationBridge? _activeOwner;

  /// Tells this terminal's cards apart from another computer's: the first
  /// bridge keeps plain tmux pane ids (`%3`), later ones add `~slot` (`%3~1`).
  final int slot;

  /// The computer's name, shown on its cards while several publish.
  final String Function()? label;

  static int _freeSlot() {
    var slot = 0;
    while (_bridges.any((bridge) => bridge.slot == slot)) {
      slot++;
    }
    return slot;
  }

  String _cardId(String paneId) => slot == 0 ? paneId : '$paneId~$slot';

  /// The bridge that published [cardId], and the pane id it stands for.
  static (TerminalNotificationBridge, String)? _route(String cardId) {
    final match = RegExp(r'^(%[0-9]+)(?:~([0-9]+))?$').firstMatch(cardId);
    if (match == null) return null;
    final slot = int.parse(match.group(2) ?? '0');
    for (final bridge in _bridges) {
      if (bridge.slot == slot && !bridge._disposed) {
        return (bridge, match.group(1)!);
      }
    }
    return null;
  }

  void setActive(bool active) {
    if (active) {
      _activeOwner = this;
    } else if (identical(_activeOwner, this)) {
      _activeOwner = null;
    }
    _channel.setMethodCallHandler(_handleNativeCall);
    publish();
  }

  static Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'sessionAction') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final action = args['action']?.toString();
      // The SSH session notification speaks for the computer on screen.
      final owner = _activeOwner;
      if (action != null && owner != null && !owner._disposed) {
        unawaited(owner.onSessionAction?.call(action));
      }
      return;
    }
    if (call.method == 'actionRejected') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final route = _route(args['id'] as String);
      route?.$1.watch.rejectAction(
        route.$2,
        'Not sent: button expired or terminal changed. Use the current button once settled.',
      );
      return;
    }
    if (call.method == 'readerAction') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      // One voice reads at a time; the bridge that started it owns it.
      final reader =
          _bridges.where((bridge) => bridge._reading != null).firstOrNull ??
          _activeOwner;
      if (reader != null) {
        unawaited(reader._readerAction(args['action'] as String));
      }
      return;
    }
    if (call.method != 'action') return;
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final action = args['action'];
    if (action == 'autoStartAll' || action == 'autoStopAll') {
      // The toggle covers every window shown, whichever computer it is on.
      for (final bridge in List.of(_bridges)) {
        if (bridge._disposed || !bridge.enabled) continue;
        if (action == 'autoStartAll') {
          unawaited(bridge.watch.startAutoRunAll());
        } else {
          bridge.watch.stopAutoRunAll();
        }
      }
      return;
    }
    final route = _route(args['id'] as String);
    if (route == null) return;
    final (bridge, paneId) = route;
    final watch = bridge.watch;
    if (action == 'listen') {
      for (final other in _bridges) {
        if (!identical(other, bridge) && other._reading != null) {
          other._stopReading();
        }
      }
      unawaited(bridge._listen(paneId, args['token'] as String));
    } else if (action == 'stop') {
      if (watch.runningPane == paneId) watch.stop();
    } else if (action == 'autoStart') {
      unawaited(watch.startAutoRun(paneId));
    } else if (action == 'autoStop') {
      watch.stopAutoRun(paneId);
    } else {
      unawaited(watch.act(paneId, action as String, args['token'] as String));
    }
  }

  static const _channel = MethodChannel('devota/terminal_notifications');
  final TerminalWatchController watch;
  final Future<void> Function(String action)? onSessionAction;
  bool enabled = true;
  final deliveryStatus = ValueNotifier<String?>(null);
  static Timer? _publishTimer;
  bool _disposed = false;
  static int _publishVersion = 0;
  ConclusionReading? _reading;
  String? _readingToken;
  int _historyLines = 120;
  int _request = 0;
  String? _readerError;
  String? _errorPane;
  void publish() {
    if (_disposed) return;
    final reading = _reading;
    if (reading != null) {
      final bindings = watch.bindings.where((b) => b.pane.id == reading.paneId);
      if (!enabled ||
          bindings.isEmpty ||
          watch.token(bindings.first) != _readingToken ||
          watch.observations[reading.paneId]?.error != null ||
          watch.runningPane == reading.paneId) {
        _stopReading();
      }
    }
    _schedulePublish();
  }

  static void _schedulePublish() {
    _publishTimer?.cancel();
    _publishTimer = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_publish()),
    );
  }

  void _stopReading() {
    _request++;
    _reading = null;
    _readingToken = null;
    unawaited(
      _channel.invokeMethod<void>('stopReading').catchError((Object _) {}),
    );
  }

  Future<void> _listen(String paneId, String token) async {
    _stopReading();
    final request = _request;
    _readerError = null;
    _errorPane = paneId;
    try {
      final source = await watch.conclusion(paneId, token);
      if (request != _request || !enabled) return;
      final binding = watch.bindings.firstWhere((b) => b.pane.id == paneId);
      _reading = ConclusionReading(paneId, binding.pane.label, source);
      _readingToken = token;
      _historyLines = 120;
      await _speak();
    } catch (_) {
      if (request == _request) {
        _readerError =
            'Reading unavailable: terminal changed or offline voice missing.';
        publish();
      }
    }
  }

  Future<void> _speak() async {
    final reading = _reading;
    if (reading == null) return;
    await _channel.invokeMethod<void>('speak', {
      'text': reading.text,
      'title': reading.title,
      'earlier': reading.hasEarlier || _historyLines < 800,
    });
  }

  Future<void> _readerAction(String action) async {
    if (action == 'stopReading' || action == 'interrupted') {
      _stopReading();
      return;
    }
    final reading = _reading;
    final token = _readingToken;
    if (reading == null || token == null) return;
    final request = _request;
    try {
      if (action == 'earlier') {
        if (reading.hasEarlier) {
          reading.earlier();
        } else if (_historyLines < 800) {
          final nextLines = (_historyLines + 120).clamp(120, 800);
          final source = await watch.conclusion(
            reading.paneId,
            token,
            lines: nextLines,
          );
          if (request != _request) return;
          if (!source.endsWith(reading.source)) {
            throw StateError('Terminal history changed');
          }
          _historyLines = source == reading.source ? 800 : nextLines;
          final expanded = ConclusionReading(
            reading.paneId,
            reading.title,
            source,
          );
          while (expanded.hasEarlier &&
              expanded.text.length <= reading.text.length) {
            expanded.earlier();
          }
          _reading = expanded;
        }
      } else if (action != 'replay') {
        return;
      }
      await _speak();
    } catch (_) {
      if (request == _request) {
        _readerError = 'Could not read earlier text or play the offline voice.';
        _errorPane = reading.paneId;
        _stopReading();
        publish();
      }
    }
  }

  /// This bridge's cards, under ids that route back to it.
  List<Map<String, Object>> _cards({required bool named}) {
    if (!enabled || _disposed) return const [];
    final name = named ? label?.call().trim() ?? '' : '';
    return watch.cards.map((card) {
      final id = card['id'] as String;
      return <String, Object>{
        ...card,
        'id': _cardId(id),
        if (name.isNotEmpty) 'title': '$name · ${card['title']}',
        if (_readerError != null && id == _errorPane)
          'status': '${card['status']} · $_readerError',
      };
    }).toList();
  }

  static Future<Map<Object?, Object?>?> _publish() async {
    final live = _bridges.where((bridge) => !bridge._disposed).toList();
    if (live.isEmpty) return null;
    // The computer on screen first, then the others in the order they opened.
    live.sort((a, b) {
      if (identical(a, _activeOwner)) return -1;
      if (identical(b, _activeOwner)) return 1;
      return a.slot.compareTo(b.slot);
    });
    final contributing = live.where(
      (bridge) => bridge.enabled && bridge.watch.bindings.isNotEmpty,
    );
    final named = contributing.length > 1;
    final cards = [for (final bridge in live) ...bridge._cards(named: named)];
    final version = ++_publishVersion;
    void report(String status) {
      for (final bridge in live) {
        if (!bridge._disposed) bridge.deliveryStatus.value = status;
      }
    }

    try {
      await _channel.invokeMethod<void>('update', {'cards': cards});
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final status = await _channel.invokeMapMethod<Object?, Object?>('status');
      if (version == _publishVersion && status != null) {
        report(
          status['allowed'] != true
              ? 'Terminal macro notifications are blocked in Android settings.'
              : status['error'] != null
              ? 'Notification error: ${status['error']}'
              : 'Android reports ${status['posted']}/${status['requested']} window cards posted.',
        );
      }
      return status;
    } on MissingPluginException catch (_) {
      // Desktop terminals have no Android notification surface.
      return null;
    } on PlatformException catch (error) {
      report('Notification error: ${error.message ?? error.code}');
      return {'error': error.message ?? error.code};
    }
  }

  Future<void> verifyDelivery() async {
    _publishTimer?.cancel();
    if (watch.bindings.isNotEmpty && !enabled) {
      throw StateError(
        'Settings saved, but background SSH notifications are inactive. Reconnect and retry.',
      );
    }
    var status = await _publish();
    if (status == null || watch.bindings.isEmpty) return;
    // Allow Android's asynchronous notification posting/rate limit to settle.
    if (status['allowed'] == true && status['posted'] != status['requested']) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await _publish();
    }
    if (status != null &&
        (status['allowed'] != true ||
            status['error'] != null ||
            status['posted'] != status['requested'])) {
      throw StateError(
        'Settings saved, but ${deliveryStatus.value ?? 'Android did not confirm the window notifications.'}',
      );
    }
  }

  void dispose() {
    enabled = false;
    if (_reading != null) _stopReading();
    _disposed = true;
    _bridges.remove(this);
    if (identical(_activeOwner, this)) _activeOwner = null;
    watch.removeListener(publish);
    deliveryStatus.dispose();
    if (_bridges.isEmpty) {
      _publishTimer?.cancel();
      _publishTimer = null;
      unawaited(
        _channel
            .invokeMethod<void>('update', {'cards': []})
            .catchError((Object _) {}),
      );
      _channel.setMethodCallHandler(null);
    } else {
      // Take this terminal's cards down, keep every other computer's.
      _schedulePublish();
    }
  }
}
