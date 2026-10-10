import 'package:dio/dio.dart';

/// A command an agent proposed for this computer's terminal. It only ever
/// fills the text box; the person reads it and decides whether to send it.
class ProposedCommand {
  const ProposedCommand({
    required this.id,
    required this.text,
    this.label = '',
  });

  final int id;
  final String text;
  final String label;

  static ProposedCommand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final id = raw['id'];
    if (text is! String || text.trim().isEmpty || id is! int) return null;
    final label = raw['label'];
    return ProposedCommand(
      id: id,
      text: text.trim(),
      label: label is String ? label.trim() : '',
    );
  }
}

/// Collects the commands waiting on a computer's DevOTA server
/// (`GET /terminal/compose`). The server hands each one over once.
class TerminalComposeInbox {
  static Future<List<ProposedCommand>> take(Dio dio, String serverUrl) =>
      _take(dio, serverUrl, '/terminal/compose');

  /// Messages an agent wants said aloud (`GET /terminal/speak`), in the same
  /// shape; their text may span several lines.
  static Future<List<ProposedCommand>> takeSpeech(Dio dio, String serverUrl) =>
      _take(dio, serverUrl, '/terminal/speak');

  static Future<List<ProposedCommand>> _take(
    Dio dio,
    String serverUrl,
    String path,
  ) async {
    final base = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return const [];
    final resp = await dio.get<Object?>(
      '$base$path',
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.json,
      ),
    );
    final data = resp.data;
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return [for (final item in items) ?ProposedCommand.fromJson(item)];
  }
}
