import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Signing a computer's CLI in from the phone (`gh auth login`, `codex login`,
/// `gcloud auth login`, ...). Command-line sign-ins take one of two shapes:
///
/// * a device code: the terminal shows a link and a short code, the person
///   opens the link anywhere and types the code, and the CLI waits for the
///   provider to confirm. The phone only needs the link and the code.
/// * a localhost callback: after signing in, the browser is sent back to
///   `http://localhost:<port>/...` on the computer, where the CLI listens. On a
///   phone that address is the phone itself, so DevOTA listens on the same
///   port on the phone and passes the request over its SSH connection to
///   `127.0.0.1:<port>` on the computer ([AuthCallbackRelay]).
class AuthPrompt {
  const AuthPrompt({
    required this.url,
    this.code,
    this.callbackPort,
    this.callbackPath,
    this.needsEnter = false,
  });

  /// The sign-in link to open in the phone's browser.
  final String url;

  /// A one-time device code shown with the link, if any.
  final String? code;

  /// Where the provider sends the browser back to on the computer.
  final int? callbackPort;
  final String? callbackPath;

  /// The CLI waits for Enter before it starts waiting for the sign-in
  /// (`gh`: "Press Enter to open github.com in your browser...").
  final bool needsEnter;
}

final _url = RegExp(r'''https?://[^\s'"<>`]+''');
final _codeAfterWord = RegExp(
  r'\bcode\b[^A-Za-z0-9\n]{0,20}([A-Z0-9]{4,5}-[A-Z0-9]{4,5})\b',
  caseSensitive: false,
);
final _dashedCode = RegExp(r'\b([A-Z0-9]{4}-[A-Z0-9]{4,5})\b');
const _authWords = [
  'login',
  'oauth',
  'authorize',
  'auth',
  'device',
  'signin',
  'sign-in',
  'activate',
  'consent',
];

bool _isLoopbackHost(String host) =>
    host == 'localhost' ||
    host == '127.0.0.1' ||
    host == '[::1]' ||
    host == '::1';

/// `gh` prints no link, only "Press Enter to open github.com in your
/// browser..." after the code; its device page is `https://<host>/login/device`.
final _ghEnterPrompt = RegExp(
  r'press enter to open ([A-Za-z0-9.-]+\.[A-Za-z]{2,}) in your browser',
  caseSensitive: false,
);

/// Finds the newest sign-in link (and code) in [screen], the terminal text with
/// wrapped lines joined. Returns null when there is none.
AuthPrompt? findAuthPrompt(String screen) {
  int score(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return -1;
    if (_isLoopbackHost(uri.host)) return 0; // the CLI's own listener
    final lower = raw.toLowerCase();
    var points = 1;
    if (_callbackOf(uri) != null) points += 4;
    if (_authWords.any(lower.contains)) points += 2;
    return points;
  }

  String? best;
  var bestAt = -1;
  var bestScore = 0;
  for (final match in _url.allMatches(screen)) {
    final candidate = match
        .group(0)!
        .replaceFirst(RegExp(r'[.,;:)\]}>]+$'), '');
    final points = score(candidate);
    // The newest of the best: a later prompt replaces an earlier one.
    if (points > 0 && points >= bestScore) {
      best = candidate;
      bestAt = match.start;
      bestScore = points;
    }
  }
  final enter = _ghEnterPrompt.allMatches(screen).lastOrNull;
  final code =
      _codeAfterWord.allMatches(screen).lastOrNull?.group(1) ??
      _dashedCode.allMatches(screen).lastOrNull?.group(1);
  if (enter != null && enter.start > bestAt) {
    return AuthPrompt(
      url: 'https://${enter.group(1)!.toLowerCase()}/login/device',
      code: code?.toUpperCase(),
      needsEnter: true,
    );
  }
  if (best == null) return null;
  final callback = _callbackOf(Uri.parse(best));
  return AuthPrompt(
    url: best,
    code: code?.toUpperCase(),
    callbackPort: callback?.port,
    callbackPath: callback?.path,
  );
}

Uri? _callbackOf(Uri uri) {
  for (final key in const ['redirect_uri', 'redirect_url', 'redirect']) {
    final value = uri.queryParameters[key];
    if (value == null) continue;
    final target = Uri.tryParse(value);
    if (target != null &&
        target.scheme == 'http' &&
        _isLoopbackHost(target.host) &&
        target.hasPort) {
      return target;
    }
  }
  return null;
}

/// The answer the computer's CLI gave to a relayed request.
class RelayedResponse {
  const RelayedResponse(this.status, this.headers, this.body);

  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

/// Sends `GET http://127.0.0.1:<port><pathAndQuery>` on the computer and
/// returns the answer (the terminal runs it over SSH).
typedef RelayForward =
    Future<RelayedResponse> Function(int port, String pathAndQuery);

/// The characters a relayed path may hold; anything else is refused before it
/// reaches a shell on the computer.
final _safePath = RegExp(r'^/[A-Za-z0-9\-._~!&*+,;=:@%/?]*$');

bool isRelayablePath(String pathAndQuery) =>
    pathAndQuery.length <= 8192 && _safePath.hasMatch(pathAndQuery);

/// The shell command that replays a callback on the computer: curl prints the
/// status line and headers, then the body.
String relayCurlCommand(int port, String pathAndQuery) {
  if (port < 1 || port > 65535 || !isRelayablePath(pathAndQuery)) {
    throw ArgumentError('Refusing to relay that address');
  }
  final url = "http://127.0.0.1:$port$pathAndQuery".replaceAll("'", "'\\''");
  return "curl -sS -i --max-time 25 '$url'";
}

/// Parses `curl -i` output (the final response when curl did not follow
/// redirects).
RelayedResponse parseCurlResponse(List<int> bytes) {
  var start = 0;
  // Skip interim responses (100 Continue) to the last header block.
  while (true) {
    final end = _indexOf(bytes, const [13, 10, 13, 10], start);
    final altEnd = _indexOf(bytes, const [10, 10], start);
    final (headerEnd, sepLength) = end >= 0 && (altEnd < 0 || end < altEnd)
        ? (end, 4)
        : (altEnd, 2);
    if (headerEnd < 0) {
      throw const FormatException('No response from the computer');
    }
    final head = latin1.decode(bytes.sublist(start, headerEnd));
    final lines = head.split(RegExp(r'\r?\n'));
    final status =
        int.tryParse(lines.first.split(' ').elementAtOrNull(1) ?? '') ?? 0;
    if (status == 0) throw FormatException('Unexpected reply: ${lines.first}');
    if (status == 100) {
      start = headerEnd + sepLength;
      continue;
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon).trim().toLowerCase()] = line
            .substring(colon + 1)
            .trim();
      }
    }
    return RelayedResponse(
      status,
      headers,
      bytes.sublist(headerEnd + sepLength),
    );
  }
}

int _indexOf(List<int> data, List<int> pattern, int from) {
  outer:
  for (var i = from; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Listens on the phone's loopback at the CLI's callback port for one sign-in
/// and relays each request to the computer. Closes [idleAfterCallback] after
/// the last request, or after [lifetime] if the sign-in never returns.
class AuthCallbackRelay {
  AuthCallbackRelay({
    required this.port,
    required this.forward,
    this.lifetime = const Duration(minutes: 10),
    this.idleAfterCallback = const Duration(seconds: 20),
    this.onEvent,
  });

  final int port;
  final RelayForward forward;
  final Duration lifetime;
  final Duration idleAfterCallback;

  /// Human-readable progress for the terminal's status line.
  final void Function(String message)? onEvent;

  final _servers = <HttpServer>[];
  Timer? _closer;
  bool _closed = false;
  int relayed = 0;

  bool get isOpen => !_closed && _servers.isNotEmpty;

  Future<void> start() async {
    // The browser may resolve localhost to either loopback address.
    for (final address in [
      InternetAddress.loopbackIPv4,
      InternetAddress.loopbackIPv6,
    ]) {
      try {
        final server = await HttpServer.bind(address, port, shared: true);
        _servers.add(server);
        server.listen(_handle, onError: (Object _) {});
      } catch (_) {
        // One family is enough; IPv6 loopback is missing on some phones.
      }
    }
    if (_servers.isEmpty) {
      throw StateError('Port $port is busy on this phone');
    }
    _closer = Timer(lifetime, close);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final target = request.uri.toString();
    try {
      if (request.method != 'GET' || !isRelayablePath(target)) {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }
      final answer = await forward(port, target);
      relayed++;
      onEvent?.call(
        'Relayed the sign-in return to the computer (HTTP ${answer.status}).',
      );
      response.statusCode = answer.status;
      for (final header in const ['content-type', 'location']) {
        final value = answer.headers[header];
        if (value != null) response.headers.set(header, value);
      }
      response.add(answer.body);
      await response.close();
    } catch (error) {
      onEvent?.call('Could not reach the computer for the sign-in: $error');
      response.statusCode = HttpStatus.badGateway;
      response.headers.contentType = ContentType.text;
      response.write(
        'DevOTA could not pass this sign-in to your computer: $error',
      );
      await response.close();
    } finally {
      _closer?.cancel();
      _closer = Timer(idleAfterCallback, close);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closer?.cancel();
    for (final server in _servers) {
      await server.close(force: true);
    }
    _servers.clear();
  }
}
