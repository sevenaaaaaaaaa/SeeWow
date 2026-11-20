import '../metadata/cover_generator.dart';
import '../metadata/custom_scraper.dart';
import '../metadata/tmdb_client.dart';
import '../playback/voice_translation.dart';
import '../sources/native_bridge.dart';
import '../watch_ai/watch_ai_settings.dart';

/// What the settings page is allowed to claim about one AI service.
///
/// The settings page used to show a live status for exactly one row (the
/// model) and say nothing about the other five, so "is my cover service even
/// connected?" had no answer short of opening every dialog. This type is the
/// data source that fixes it: it is read from the same stores the dialogs
/// write, so a pill can never disagree with the dialog behind it.
class AiServiceStatus {
  const AiServiceStatus({this.configured = false, this.detail = ''});

  final bool configured;

  /// A short, true hint — a model name or a count. Empty when there is
  /// nothing honest to say.
  final String detail;

  static const unknown = AiServiceStatus();
}

/// Everything the AI group can state at a glance.
class AiStatusSnapshot {
  const AiStatusSnapshot({
    required this.watchAi,
    required this.voice,
    required this.cover,
    required this.metadata,
    required this.scrapers,
  });

  final AiServiceStatus watchAi;
  final AiServiceStatus voice;
  final AiServiceStatus cover;
  final AiServiceStatus metadata;
  final AiServiceStatus scrapers;

  /// How many of the five optional services are connected. The model itself is
  /// counted by the page (it lives on the agent controller, not on disk).
  int get configuredCount => [
    watchAi,
    voice,
    cover,
    metadata,
    scrapers,
  ].where((s) => s.configured).length;

  static Future<AiStatusSnapshot> load() async {
    final watch = WatchAiSettings.I.config;

    AiServiceStatus voice = AiServiceStatus.unknown;
    try {
      final config = await VoiceTranslationConfig.load();
      voice = AiServiceStatus(
        configured: config.endpoint.isNotEmpty && config.model.isNotEmpty,
        detail: config.endpoint.isEmpty ? '' : config.model,
      );
    } catch (_) {
      // A broken config file must not take the settings page down.
    }

    AiServiceStatus cover = AiServiceStatus.unknown;
    try {
      final config = await CoverGenerationConfig.load();
      cover = AiServiceStatus(
        configured: config.endpoint.isNotEmpty && config.model.isNotEmpty,
        detail: config.endpoint.isEmpty ? '' : config.model,
      );
    } catch (_) {
      // Same rule as above: state what is known, not what is hoped.
    }

    AiServiceStatus metadata = AiServiceStatus.unknown;
    try {
      final token = await NativeBridge.secretRead(TmdbClient.tokenKey) ?? '';
      metadata = AiServiceStatus(
        configured: token.isNotEmpty,
        detail: token.isEmpty ? '' : 'TMDB',
      );
    } catch (_) {}

    AiServiceStatus scrapers = AiServiceStatus.unknown;
    try {
      final profiles = await CustomScraperRepository().load();
      scrapers = AiServiceStatus(
        configured: profiles.isNotEmpty,
        detail: profiles.isEmpty
            ? ''
            : [profiles.length.toString(), '个'].join(' '),
      );
    } catch (_) {}

    return AiStatusSnapshot(
      watchAi: AiServiceStatus(
        configured: watch.configured,
        detail: watch.configured
            ? (watch.enabled
                  ? watch.model
                  : [watch.model, '已关闭'].join(' · '))
            : '',
      ),
      voice: voice,
      cover: cover,
      metadata: metadata,
      scrapers: scrapers,
    );
  }
}
