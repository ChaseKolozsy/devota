import 'dart:convert';
import 'package:flutter/services.dart';
import 'terminal_conclusion.dart';

/// No remote model: OCR and keyword rules run on the phone.
Future<String> reviewTerminalLocally(String source) async {
  const channel = MethodChannel('devota/terminal_review');
  final ocr = await channel.invokeMethod<String>('recognizeSnapshot', {
    'text': cleanTerminalConclusion(source),
  });
  final original = classifyTerminalText(source);
  final recognized = classifyTerminalText(normalizeOcrText(ocr ?? ''));
  // OCR must never introduce or erase a caveat to manufacture success.
  final verdict = original.status == recognized.status
      ? original
      : ConclusionVerdict.unknown;
  return jsonEncode({
    'status': verdict.status,
    'reason': verdict.reason,
    'evidence': verdict.evidence,
  });
}

/// Common Latin OCR confusions inside counts: "2O/2O", "O failed".
String normalizeOcrText(String text) => text
    .replaceAllMapped(RegExp(r'(?<=[\d/])[Oo]|[Oo](?=[\d/])'), (_) => '0')
    .replaceAllMapped(
      RegExp(r'\b[Oo](?=\s+(?:failed|failures?|skipped|unresolved|errors?)\b)'),
      (_) => '0',
    )
    .replaceAll(RegExp(r'(?<=:\s?)[Oo]\b'), '0');

/// The line DevOTA macros ask agents to end with, e.g.
/// `RESULT: DONE 20/20 approved, 0 failed, 0 skipped`.
final _resultLine = RegExp(
  r'RESULT\s*[:;]\s*(DONE|CHECK|EMPTY)\b(.*)$',
  multiLine: true,
);
const _numberWords =
    'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
    'thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty';
const _problemWords =
    r'(?:failed|failures?|failing|errors?|skipped|unresolved|rejected|'
    r'blocked|unapproved|not approved|missing)';
final _nonzeroProblem = RegExp(
  '\\b(?:[1-9]\\d*|$_numberWords)\\s+'
  '(?:(?!(?:no|zero|none)\\b)[a-zA-Z-]+\\s+){0,3}?$_problemWords\\b|'
  '\\b$_problemWords\\s*[:=]\\s*(?:[1-9]\\d*|$_numberWords)\\b',
  caseSensitive: false,
);
final _zeroProblem = RegExp(
  '\\b(?:0|zero|no|none)\\s+(?:[a-zA-Z-]+\\s+){0,3}?$_problemWords\\b|'
  '\\b$_problemWords\\s*[:=]\\s*(?:0|zero|none)\\b',
  caseSensitive: false,
);
final _hardAttention = RegExp(
  r"\b(?:not (?:done|complete|completed|finished|verified|approved|"
  r"submitted|recovered|resolved|fixed|repaired)|could not|couldn't|cannot|"
  r"can't|unable to|blocked|unfinished|unverified|"
  r'(?:tests?|checks?|build|macro|push|verification) (?:failed|fails)|'
  r'(?:failed|failing) (?:tests?|checks?|build)|'
  r'needs? (?:your |user )?(?:approval|confirmation|attention|input|decision)|'
  r'(?:please|you (?:must|need to|should))\s+\w+|'
  r'(?:still|remains?) (?:pending|incomplete|failing|unresolved)|'
  r'(?:not|never) (?:committed|pushed|rebuilt))\b',
  caseSensitive: false,
);
final _emptyQueue = RegExp(
  r'\b(?:roster|queue) (?:is |was )?empty\b|'
  r'\bnothing (?:was |is )?(?:assigned|queued|left to)\b|'
  r'\bno (?:topics|words|lessons|items) (?:were |are )?(?:assigned|queued|available)\b',
  caseSensitive: false,
);
final _recovered = RegExp(
  r'\b(?:recovered|resolved|corrected|repaired|fixed|retried successfully)\b',
  caseSensitive: false,
);
final _hedge = RegExp(
  r"^(?:if|when|once)\b|\bI'll\b|\bI will\b|\bI'm (?:using|going|now|starting|"
  r'running|checking|waiting)\b|\bnext,? I\b|\bwill (?:now|then|next)\b|'
  r'\bworking on\b|\bin progress\b|\bstill running\b|\bwaiting for\b|'
  r'^working\b|esc to interrupt',
  caseSensitive: false,
);
final _countWord = '(?:\\d+|$_numberWords)';
final _doneVerb =
    r'(approved|submitted|completed|complete|done|created|published|'
    r'passed|finished|staged|drafted)';
final _allDone = RegExp(
  '\\ball\\s+(?:the\\s+)?($_countWord)\\b[^.;!?]{0,180}\\b$_doneVerb\\b',
  caseSensitive: false,
);
final _fullCount = RegExp(
  '\\b(\\d+)\\s*(?:/|out of|of)\\s*(\\d+)\\b[^.;!?]{0,40}?\\b$_doneVerb\\b',
  caseSensitive: false,
);
final _countDone = RegExp(
  '\\b($_countWord)\\b[^.;!?]{0,160}\\b(approved|submitted|published)\\b',
  caseSensitive: false,
);
final _generalDone = RegExp(
  r'\b(?:all (?:required )?(?:work|tasks?|items?|changes) (?:is |are )?'
  r'(?:complete|completed|done)|(?:implemented|fixed|completed|finished)\b.{0,120}'
  r'\b(?:verified|tested|checks passed)|committed and pushed|'
  r'changes (?:are )?(?:complete|completed))\b',
  caseSensitive: false,
);
final _leadDone = RegExp(
  r'^\s*(?:done|completed?|finished|all done)\b',
  caseSensitive: false,
);

ConclusionVerdict classifyTerminalText(String raw) {
  final lines = _reportLines(raw);
  if (lines == null || lines.isEmpty) return ConclusionVerdict.unknown;
  final result = _resultVerdict(lines);
  if (result != null) return result;

  // Wrapped terminal lines are rejoined so keywords split across a wrap still
  // match. Offsets map back to a source line for evidence.
  final starts = <int>[];
  final buffer = StringBuffer();
  for (final line in lines) {
    if (buffer.isNotEmpty) buffer.write(' ');
    starts.add(buffer.length);
    buffer.write(line.trim());
  }
  final text = buffer.toString().replaceAll('’', "'");
  String evidenceAt(int offset) {
    var index = 0;
    while (index + 1 < starts.length && starts[index + 1] <= offset) {
      index++;
    }
    final line = lines[index].trim();
    return line.length > 300 ? line.substring(0, 300) : line;
  }

  final sentences = <(int, String)>[];
  var start = 0;
  for (final match in RegExp(r'(?<=[.!?;])\s+|\s+·\s+').allMatches(text)) {
    sentences.add((start, text.substring(start, match.start)));
    start = match.end;
  }
  if (start < text.length) sentences.add((start, text.substring(start)));

  var zero = false;
  for (final (offset, sentence) in sentences) {
    if (_emptyQueue.hasMatch(sentence)) {
      return ConclusionVerdict(
        'needs_attention',
        'Queue empty, nothing assigned',
        evidenceAt(offset),
      );
    }
    // "No topics remain unresolved", "None skipped": a clean zero report.
    if (RegExp(
      r'^\s*(?:no|none|nothing|zero|0)\b',
      caseSensitive: false,
    ).hasMatch(sentence)) {
      if (_zeroProblem.hasMatch(sentence)) zero = true;
      continue;
    }
    if (_hardAttention.hasMatch(sentence) ||
        _nonzeroProblem.hasMatch(sentence) && !_recovered.hasMatch(sentence)) {
      return ConclusionVerdict(
        'needs_attention',
        _shortReason(sentence),
        evidenceAt(offset),
      );
    }
    for (final match in RegExp(
      r'\b(\d+)\s*(?:/|out of|of)\s*(\d+)\b',
    ).allMatches(sentence)) {
      final done = int.parse(match[1]!), total = int.parse(match[2]!);
      if (done < total &&
          RegExp(_doneVerb, caseSensitive: false).hasMatch(sentence)) {
        return ConclusionVerdict(
          'needs_attention',
          'Partial: $done/$total',
          evidenceAt(offset),
        );
      }
    }
    if (_zeroProblem.hasMatch(sentence)) zero = true;
  }
  if (sentences.last.$2.trimRight().endsWith('?')) {
    return ConclusionVerdict(
      'needs_attention',
      'Asks you a question',
      evidenceAt(sentences.last.$1),
    );
  }
  // Plans and conditionals are not completion reports.
  if (sentences.any((s) => _hedge.hasMatch(s.$2.trim()))) {
    return ConclusionVerdict.unknown;
  }

  for (final (offset, sentence) in sentences) {
    final all = _allDone.firstMatch(sentence);
    if (all != null) {
      return _done(
        'all ${all[1]} ${all[2]!.toLowerCase()}',
        zero,
        evidenceAt(offset + all.start),
      );
    }
    final full = _fullCount.firstMatch(sentence);
    if (full != null && full[1] == full[2]) {
      return _done(
        '${full[1]}/${full[2]} ${full[3]!.toLowerCase()}',
        zero,
        evidenceAt(offset + full.start),
      );
    }
  }
  final lead = _leadDone.hasMatch(text);
  for (final (offset, sentence) in sentences) {
    final count = _countDone.firstMatch(sentence);
    if (count != null && (zero || lead)) {
      return _done(
        '${count[1]} ${count[2]!.toLowerCase()}',
        zero,
        evidenceAt(offset + count.start),
      );
    }
  }
  for (final (offset, sentence) in sentences) {
    final general = _generalDone.firstMatch(sentence);
    if (general != null) {
      return _done(
        'reported complete',
        zero,
        evidenceAt(offset + general.start),
      );
    }
  }
  return ConclusionVerdict.unknown;
}

ConclusionVerdict _done(String summary, bool zero, String evidence) =>
    ConclusionVerdict(
      'reported_success',
      zero ? '$summary, 0 failed' : summary,
      evidence,
    );

String _shortReason(String sentence) {
  final trimmed = sentence.trim();
  return trimmed.length <= 80 ? trimmed : '${trimmed.substring(0, 77)}...';
}

ConclusionVerdict? _resultVerdict(List<String> lines) {
  for (final line in lines.reversed) {
    final match = _resultLine.firstMatch(line);
    if (match == null) continue;
    final evidence = line.trim().length > 300
        ? line.trim().substring(0, 300)
        : line.trim();
    final detail = match[2]!.replaceFirst(RegExp(r'^[\s:—–-]+'), '').trim();
    final summary = detail.isEmpty ? match[1]! : detail;
    final reason = summary.length > 80 ? summary.substring(0, 80) : summary;
    if (match[1] == 'EMPTY') {
      return ConclusionVerdict('needs_attention', 'Queue empty', evidence);
    }
    final count = RegExp(r'\b(\d+)\s*/\s*(\d+)\b').firstMatch(detail);
    final shortfall =
        count != null && int.parse(count[1]!) < int.parse(count[2]!);
    if (match[1] == 'CHECK' || shortfall || _nonzeroProblem.hasMatch(detail)) {
      return ConclusionVerdict('needs_attention', reason, evidence);
    }
    // A template echoed from the macro prompt has no real counts.
    if (count == null) continue;
    return ConclusionVerdict('reported_success', reason, evidence);
  }
  return null;
}

/// The latest report, without the agent's own input box and footer. Returns
/// null when a newer submitted prompt follows the report.
List<String>? _reportLines(String raw) {
  final prompt = RegExp(r'^\s*[❯›>]');
  var rawLines = raw
      .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  // Codex/Claude Code keep an input box (empty or with placeholder text) and a
  // status footer under the last reply; that box is not a new request.
  for (var i = rawLines.length - 1; i >= 0 && i >= rawLines.length - 8; i--) {
    if (RegExp(r'^\s*[●⏺•]').hasMatch(rawLines[i])) break; // newer reply
    if (prompt.hasMatch(rawLines[i])) {
      rawLines = rawLines.sublist(0, i);
      break;
    }
  }
  // Any other prompt line is a newer request echoed after the report.
  if (rawLines.any((line) => RegExp(r'^\s*[❯›>]\s*\S').hasMatch(line))) {
    return null;
  }
  return cleanTerminalConclusion(rawLines.join('\n'))
      .split('\n')
      .where(
        (line) =>
            line.trim().isNotEmpty &&
            !RegExp(
              r'^\s*(?:⏵⏵|⏸|✔ Update installed|\? for shortcuts|'
              r'← for agents)',
            ).hasMatch(line),
      )
      .toList();
}

/// Bound review to the bottom of the pane, separating the last bullet-style
/// assistant message (Claude Code ●/⏺, Codex •). Earlier messages in the same
/// turn are superseded progress updates. Listening keeps its own history.
String terminalReviewExcerpt(String raw) {
  final markers = RegExp(
    r'^\s*[●⏺•]\s+',
    multiLine: true,
  ).allMatches(raw).toList();
  if (markers.isNotEmpty) raw = raw.substring(markers.last.start);
  var lines = raw.split('\n');
  if (lines.length > 40) lines = lines.sublist(lines.length - 40);
  var text = lines.join('\n').trim();
  if (text.length > 6000) {
    text = text.substring(text.length - 6000);
    final boundary = text.indexOf('\n');
    if (boundary >= 0) text = text.substring(boundary + 1);
  }
  return text;
}
