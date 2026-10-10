import 'package:devota/voice/agent_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// What an agent's devota_speak text sounds like on the phone.
void main() {
  test('markdown is not read out symbol by symbol', () {
    expect(
      speakableMessage(
        '## Done\n'
        '- **Tests** pass in `app/`\n'
        '> see [the PR](https://github.com/x/y/pull/1) or https://x.io/a\n'
        '```\nflutter test\n```\nShall I push?',
      ),
      'Done\nTests pass in app/\nsee the PR or a link\n (code on screen) \n'
      'Shall I push?',
    );
  });

  test('the sender comes first, in the same breath as the message', () {
    expect(agentMessageChunks('Claude', 'Build finished. All green.'), [
      'Claude says: Build finished. All green.',
    ]);
    expect(agentMessageChunks('', 'Done.'), ['Done.']);
    expect(agentMessageChunks('Claude', ' ** '), isEmpty);
  });
}
