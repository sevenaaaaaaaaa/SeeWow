/// Common Chat Completions platforms, so nobody has to recall a base URL.
///
/// Every endpoint here must be a complete Chat Completions URL: the app posts
/// JSON straight to it and never guesses a vendor-specific path at request
/// time. [normalizeChatEndpoint] is the single place that turns a half-typed
/// address (`api.deepseek.com`, `http://localhost:11434`, `…/v1`) into one.
class ModelProvider {
  const ModelProvider({
    required this.id,
    required this.label,
    required this.endpoint,
    required this.models,
    required this.note,
    this.needsKey = true,
  });

  final String id;
  final String label;
  final String endpoint;
  final List<String> models;
  final String note;
  final bool needsKey;
}

const kModelProviders = <ModelProvider>[
  ModelProvider(
    id: 'openai',
    label: 'OpenAI',
    endpoint: 'https://api.openai.com/v1/chat/completions',
    models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini'],
    note: '官方服务 · 需 API Key',
  ),
  ModelProvider(
    id: 'deepseek',
    label: 'DeepSeek 深度求索',
    endpoint: 'https://api.deepseek.com/v1/chat/completions',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    note: '开源权重模型 · 需 API Key',
  ),
  ModelProvider(
    id: 'siliconflow',
    label: '硅基流动 SiliconFlow',
    endpoint: 'https://api.siliconflow.cn/v1/chat/completions',
    models: [
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct',
      'Qwen/Qwen2.5-7B-Instruct',
    ],
    note: '一个 Key 调用多种开源模型 · 需 API Key',
  ),
  ModelProvider(
    id: 'openrouter',
    label: 'OpenRouter',
    endpoint: 'https://openrouter.ai/api/v1/chat/completions',
    models: [
      'deepseek/deepseek-chat',
      'qwen/qwen-2.5-72b-instruct',
      'meta-llama/llama-3.3-70b-instruct',
    ],
    note: '聚合多家开源模型 · 需 API Key',
  ),
  ModelProvider(
    id: 'dashscope',
    label: '通义千问 · 百炼',
    endpoint:
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    models: ['qwen-plus', 'qwen-max', 'qwen-turbo'],
    note: '兼容模式 · 需 API Key',
  ),
  ModelProvider(
    id: 'zhipu',
    label: '智谱 GLM',
    endpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    models: ['glm-4-flash', 'glm-4-plus', 'glm-4-air'],
    note: '需 API Key · glm-4-flash 有免费额度',
  ),
  ModelProvider(
    id: 'moonshot',
    label: 'Moonshot Kimi',
    endpoint: 'https://api.moonshot.cn/v1/chat/completions',
    models: ['moonshot-v1-8k', 'moonshot-v1-32k'],
    note: '需 API Key',
  ),
  ModelProvider(
    id: 'ark',
    label: '火山方舟 · 豆包',
    endpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    models: ['doubao-1.5-pro-32k', 'doubao-1.5-lite-32k'],
    note: '推理接入点需与服务端名称一致 · 需 API Key',
  ),
  ModelProvider(
    id: 'ollama',
    label: 'Ollama（本机）',
    endpoint: 'http://localhost:11434/v1/chat/completions',
    models: ['qwen2.5', 'llama3.1', 'deepseek-r1'],
    note: '本机离线 · 免 Key · 需先 ollama pull 模型',
    needsKey: false,
  ),
  ModelProvider(
    id: 'lmstudio',
    label: 'LM Studio（本机）',
    endpoint: 'http://localhost:1234/v1/chat/completions',
    models: ['qwen2.5-7b-instruct', 'llama-3.1-8b-instruct'],
    note: '本机离线 · 免 Key · 在 LM Studio 加载模型后使用',
    needsKey: false,
  ),
];

ModelProvider? modelProviderById(String id) =>
    kModelProviders.where((p) => p.id == id).firstOrNull;

/// Turns what a person actually types into a complete Chat Completions URL.
///
/// - `api.deepseek.com` → `https://api.deepseek.com/v1/chat/completions`
/// - `http://localhost:11434` → `http://localhost:11434/v1/chat/completions`
/// - `https://api.openai.com/v1/` → `https://api.openai.com/v1/chat/completions`
/// - anything already ending in `/chat/completions` is kept as is.
///
/// Input that cannot be a host (no dot, no scheme, not a loopback name) is
/// returned untouched, so the existing validation still rejects it instead of
/// the normalizer quietly inventing a domain.
String normalizeChatEndpoint(String input) {
  var raw = input.trim();
  if (raw.isEmpty) return '';
  if (!raw.contains('://')) {
    final loopback = RegExp(
      r'^(localhost|127\.\d|\[::1\]|::1)',
      caseSensitive: false,
    ).hasMatch(raw);
    final hostPart = raw
        .split(RegExp(r'[/?#]'))
        .first
        .replaceFirst(RegExp(r':\d+$'), '');
    if (!loopback && !hostPart.contains('.')) return raw;
    raw = '${loopback ? 'http' : 'https'}://$raw';
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return raw;
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) {
    path = '/v1/chat/completions';
  } else if (!path.endsWith('/chat/completions')) {
    path = '$path/chat/completions';
  }
  return uri.replace(path: path).toString();
}

bool looksLikeHtml(String body) => body.trimLeft().startsWith('<');
