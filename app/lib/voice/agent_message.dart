/// Messages an agent asks the phone to say aloud (`devota_speak`).
library;

import 'screen_reader.dart';

/// [text] as it should sound: markdown markers, code fences and bare links
/// that would be read out symbol by symbol are dropped or named.
String speakableMessage(String text) {
  var s = text.replaceAll('\r', '');
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' (code on screen) ');
  s = s.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1)!,
  );
  s = s.replaceAll(RegExp(r'https?://\S+'), 'a link');
  s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  s = s.replaceAll(RegExp(r'[`*_]{1,3}'), '');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  return s.trim();
}

/// Who it is from, then the message, in chunks for the phone's reader.
List<String> agentMessageChunks(String label, String text) {
  final body = speakableMessage(text);
  if (body.isEmpty) return const [];
  final from = label.trim();
  return speechChunks(from.isEmpty ? body : '$from says: $body');
}
