import 'dart:convert';
import 'dart:io';

import 'package:devota/auth_relay.dart';
import 'package:flutter_test/flutter_test.dart';

const _codexBrowser = '''
Starting local login server on http://localhost:1455.
If your browser did not open, navigate to this URL to authenticate:

https://auth.openai.com/oauth/authorize?response_type=code&client_id=app_X&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&scope=openid%20profile&state=abc
''';

const _codexDevice = '''
Follow these steps to sign in with ChatGPT using device code authorization:

1. Open this link in your browser and sign in to your account
   https://auth.openai.com/codex/device

2. Enter this one-time code (expires in 15 minutes)
   WXYZ-12345
''';

const _gh = '''
\$ gh auth refresh -h github.com -s delete_repo
! First copy your one-time code: 3F2A-9C1B
Press Enter to open github.com in your browser...
''';

void main() {
  test('codex browser login: link plus the localhost callback port', () {
    final prompt = findAuthPrompt(_codexBrowser)!;
    expect(prompt.url, startsWith('https://auth.openai.com/oauth/authorize?'));
    expect(prompt.callbackPort, 1455);
    expect(prompt.callbackPath, '/auth/callback');
    expect(prompt.code, isNull);
    expect(prompt.needsEnter, isFalse);
  });

  test('codex device login: link and one-time code, no callback', () {
    final prompt = findAuthPrompt(_codexDevice)!;
    expect(prompt.url, 'https://auth.openai.com/codex/device');
    expect(prompt.code, 'WXYZ-12345');
    expect(prompt.callbackPort, isNull);
  });

  test('gh prints no link: its device page, the code, and Enter', () {
    final prompt = findAuthPrompt(_gh)!;
    expect(prompt.url, 'https://github.com/login/device');
    expect(prompt.code, '3F2A-9C1B');
    expect(prompt.needsEnter, isTrue);
  });

  test('the newest prompt wins and plain screens have none', () {
    expect(findAuthPrompt('ls -la\nREADME.md\n'), isNull);
    expect(findAuthPrompt('Server on http://localhost:8080/\n'), isNull);
    final prompt = findAuthPrompt('$_gh\n$_codexBrowser')!;
    expect(prompt.callbackPort, 1455);
  });

  test('relayed addresses are quoted and unsafe ones refused', () {
    expect(
      relayCurlCommand(1455, '/auth/callback?code=a1&state=b%20c'),
      "curl -sS -i --max-time 25 'http://127.0.0.1:1455/auth/callback?code=a1&state=b%20c'",
    );
    for (final bad in ["/x'; rm -rf ~;'", '/a b', 'nohost', '/\$(id)']) {
      expect(() => relayCurlCommand(1455, bad), throwsArgumentError, reason: bad);
    }
    expect(() => relayCurlCommand(0, '/'), throwsArgumentError);
  });

  test('curl -i output parses to the final status, headers and body', () {
    final raw = utf8.encode(
      'HTTP/1.1 100 Continue\r\n\r\n'
      'HTTP/1.1 302 Found\r\nLocation: /success\r\nContent-Type: text/html\r\n\r\n<b>ok</b>',
    );
    final response = parseCurlResponse(raw);
    expect(response.status, 302);
    expect(response.headers['location'], '/success');
    expect(utf8.decode(response.body), '<b>ok</b>');
  });

  test('the phone relay passes the browser callback to the computer', () async {
    final seen = <String>[];
    final relay = AuthCallbackRelay(
      port: 0,
      forward: (port, target) async {
        seen.add(target);
        return RelayedResponse(200, {'content-type': 'text/plain'}, utf8.encode('signed in'));
      },
    );
    // Port 0 cannot be the CLI's port; bind a free one the way the CLI would.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final real = AuthCallbackRelay(port: port, forward: relay.forward);
    await real.start();
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/auth/callback?code=xyz&state=s'));
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(await utf8.decodeStream(response), 'signed in');
    expect(seen, ['/auth/callback?code=xyz&state=s']);
    final post = await (await client.postUrl(Uri.parse('http://127.0.0.1:$port/x'))).close();
    expect(post.statusCode, 405);
    client.close(force: true);
    await real.close();
    expect(real.isOpen, isFalse);
  });
}
