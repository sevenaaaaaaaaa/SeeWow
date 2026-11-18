import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/model_presets.dart';

void main() {
  group('normalizeChatEndpoint', () {
    test('completes a bare platform domain', () {
      expect(
        normalizeChatEndpoint('api.deepseek.com'),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(
        normalizeChatEndpoint('  https://api.openai.com/v1 '),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        normalizeChatEndpoint('https://api.openai.com/v1/'),
        'https://api.openai.com/v1/chat/completions',
      );
    });

    test('keeps a complete endpoint untouched', () {
      const full = 'https://api.openai.com/v1/chat/completions';
      expect(normalizeChatEndpoint(full), full);
      expect(
        normalizeChatEndpoint('http://127.0.0.1:11434/v1/chat/completions'),
        'http://127.0.0.1:11434/v1/chat/completions',
      );
    });

    test('loopback shorthand becomes plain HTTP, not HTTPS', () {
      expect(
        normalizeChatEndpoint('http://localhost:11434'),
        'http://localhost:11434/v1/chat/completions',
      );
      expect(
        normalizeChatEndpoint('localhost:1234'),
        'http://localhost:1234/v1/chat/completions',
      );
    });

    test('vendor version paths keep their own prefix', () {
      expect(
        normalizeChatEndpoint('https://open.bigmodel.cn/api/paas/v4'),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
      expect(
        normalizeChatEndpoint('https://ark.cn-beijing.volces.com/api/v3'),
        'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
      );
    });

    test('junk input is left for validation to reject', () {
      expect(normalizeChatEndpoint('not a url'), 'not a url');
      expect(normalizeChatEndpoint('abc'), 'abc');
      expect(normalizeChatEndpoint(''), '');
    });

    test('every preset is a complete Chat Completions endpoint', () {
      final ids = <String>{};
      for (final provider in kModelProviders) {
        expect(ids.add(provider.id), isTrue, reason: 'duplicate ${provider.id}');
        expect(
          provider.endpoint.endsWith('/chat/completions'),
          isTrue,
          reason: provider.label,
        );
        expect(provider.models, isNotEmpty, reason: provider.label);
        expect(
          normalizeChatEndpoint(provider.endpoint),
          provider.endpoint,
          reason: provider.label,
        );
      }
      expect(kModelProviders.any((p) => !p.needsKey), isTrue, reason: '本机免 Key');
    });
  });
}
