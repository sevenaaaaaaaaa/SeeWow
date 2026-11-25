import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_controller.dart';
import '../agent/model_presets.dart';
import '../data/iptv_store.dart';
import '../design/cinema_widgets.dart';
import '../design/liquid_glass.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import 'sources_view.dart';

class AgentView extends StatefulWidget {
  const AgentView({
    super.key,
    required this.agent,
    required this.iptv,
    required this.onOpen,
  });
  final AgentController agent;
  final IPTVStore iptv;
  final ValueChanged<MediaItem> onOpen;
  @override
  State<AgentView> createState() => _AgentViewState();
}

class _AgentViewState extends State<AgentView> {
  final _prompt = TextEditingController();
  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _send() {
    if (_prompt.text.trim().isEmpty || widget.agent.busy) return;
    widget.agent.run(_prompt.text.trim());
    _prompt.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.agent,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final agent = widget.agent;
        final wide = box.maxWidth > 980;
        return ListView(
          padding: EdgeInsets.all(box.maxWidth < 700 ? 20 : 32),
          children: [
            PageIntro(
              action: OutlinedButton.icon(
                onPressed: agent.busy
                    ? null
                    : () => configureAgent(context, agent),
                icon: const Icon(Icons.tune, size: 16),
                label: Text(agent.hasModel ? agent.model : '接入 AI 模型'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      CinemaPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: WowColors.accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  agent.hasModel ? 'AI 规划 · 本地工具执行' : '本地规则模式',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                if (agent.busy)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              agent.hasModel
                                  ? '发送后，会把本次需求、类型偏好和最多 250 条影片摘要发送到你配置的模型服务。地址、路径与凭据不包含在片库摘要里。'
                                  : '当前使用可解释的规则和本地推荐。接入模型后可理解更自由的描述，并规划多步操作。',
                              style: WowType.body(12, color: WowColors.muted),
                            ),
                            const SizedBox(height: 16),
                            // ⌘/Ctrl + Enter sends. A multi-line box cannot
                            // use Enter, and a composer that can only be sent
                            // by finding a button is the slowest input in the
                            // app — this is where the user types the most.
                            CallbackShortcuts(
                              bindings: {
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                  meta: true,
                                ): _send,
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                  control: true,
                                ): _send,
                              },
                              child: TextField(
                                controller: _prompt,
                                minLines: 3,
                                maxLines: 6,
                                enabled: !agent.busy,
                                decoration: const InputDecoration(
                                  hintText: '例如：按我的口味，选几部周末想看的科幻电影，生成一份片单。',
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(fontSize: 14, height: 1.7),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '影片来自你的真实片库',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WowColors.muted,
                                    ),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: agent.busy
                                      ? (agent.cancellationRequested
                                            ? null
                                            : agent.stop)
                                      : _send,
                                  icon: Icon(
                                    agent.busy
                                        ? Icons.stop_rounded
                                        : Icons.arrow_upward,
                                    size: 17,
                                  ),
                                  label: Text(
                                    agent.busy
                                        ? (agent.cancellationRequested
                                              ? '正在停止…'
                                              : '停止后续步骤')
                                        : '开始执行',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final prompt in [
                              '按我的口味生成科幻片单',
                              '推荐一部 120 分钟内的轻松电影',
                              '检查重复影片和缺失信息',
                              '刷新片源并检查片库',
                            ])
                              ActionChip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                label: Text(
                                  prompt,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: agent.busy
                                    ? null
                                    : () => agent.run(prompt),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (agent.runs.isEmpty)
                        EmptyCinema(
                          icon: Icons.auto_awesome_outlined,
                          title: '从一个念头，到一场放映',
                          description:
                              '任务会留下执行记录。推荐结果可以加入待看，片单预览可以一键保存，连接失败也会明确告诉你。',
                          // An empty history with no button is a dead end:
                          // the most useful first command was always one tap
                          // away, but nothing said so.
                          action: GlassButton(
                            label: '先让 Agent 检查片库',
                            icon: Icons.auto_fix_high_outlined,
                            onTap: agent.busy
                                ? null
                                : () => agent.run('刷新片源并检查片库'),
                          ),
                        ),
                      for (final run in agent.runs.take(20))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _RunCard(
                            run: run,
                            agent: agent,
                            iptv: widget.iptv,
                            onOpen: widget.onOpen,
                          ),
                        ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 240,
                    child: CinemaPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('CONNECTED TO YOUR CINEMA'),
                          const SizedBox(height: 20),
                          _capability(
                            Icons.favorite_border,
                            '懂你的偏好',
                            '${agent.library.taste.genres.length} 项类型偏好 · 喜欢与观看反馈',
                          ),
                          const SizedBox(height: 22),
                          _capability(
                            Icons.video_library_outlined,
                            '读懂你的收藏',
                            '${agent.library.items.length} 个条目可检索、挑选与检查',
                          ),
                          const SizedBox(height: 22),
                          _capability(
                            Icons.hub_outlined,
                            '调用真实工具',
                            '推荐 / 搜索 / 片库体检 / 刷新来源 / 片单预览 / 链接收集',
                          ),
                          const SizedBox(height: 22),
                          _capability(
                            Icons.history,
                            '保留执行记录',
                            '${agent.runs.length} 次任务 · 最多保存最近 30 次',
                          ),
                          const SizedBox(height: 20),
                          Divider(color: WowColors.line),
                          const SizedBox(height: 12),
                          Text(
                            '链接收集只读取你提供的地址和页面；当前不支持全网搜索。文件与原片不会被 Agent 删除。',
                            style: WowType.body(11, color: WowColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    ),
  );
  Widget _capability(IconData icon, String title, String detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 17, color: WowColors.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      const SizedBox(height: 7),
      Text(detail, style: WowType.body(11, color: WowColors.muted)),
    ],
  );
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.agent,
    required this.iptv,
    required this.onOpen,
  });
  final AgentRun run;
  final AgentController agent;
  final IPTVStore iptv;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context) {
    final running = run.steps.any((s) => s.state == 'running');
    final items = run.itemIds
        .map((id) => agent.library.items.where((i) => i.id == id).firstOrNull)
        .whereType<MediaItem>()
        .toList();
    return CinemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.prompt,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                run.mode,
                style: TextStyle(fontSize: 10, color: WowColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final step in run.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step.state == 'running')
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      step.state == 'done'
                          ? Icons.check_circle_rounded
                          : step.state == 'failed' ||
                                step.state == 'interrupted'
                          ? Icons.error_outline
                          : Icons.circle_outlined,
                      size: 16,
                      color: step.state == 'done'
                          ? WowColors.success
                          : step.state == 'failed'
                          ? WowColors.error
                          : WowColors.muted,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (step.detail.isNotEmpty)
                          Text(
                            step.detail,
                            style: WowType.body(11, color: WowColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (run.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                run.summary,
                style: WowType.body(
                  12,
                  color: run.failed ? WowColors.error : WowColors.text,
                ),
              ),
            ),
          for (final url in run.candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link, size: 18),
              title: Text(
                sourceDisplayAddress(url),
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: OutlinedButton(
                onPressed: () =>
                    connectSource(context, agent.library, iptv, initial: url),
                child: const Text('连接'),
              ),
            ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 274,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, n) => SizedBox(
                  width: 132,
                  child: FilmCard(
                    item: items[n],
                    store: agent.library,
                    reason: run.reasons[items[n].id],
                    onOpen: () => onOpen(items[n]),
                  ),
                ),
              ),
            ),
          ],
          if (!running && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton.icon(
                onPressed:
                    agent.collectionExists(run) || agent.isSavingCollection(run)
                    ? null
                    : () => agent.saveCollection(run),
                icon: Icon(
                  agent.collectionExists(run)
                      ? Icons.check
                      : Icons.playlist_add,
                  size: 18,
                ),
                label: Text(
                  agent.collectionExists(run)
                      ? '已保存到我的片单'
                      : '保存${run.collectionName == null ? '结果为片单' : '「${run.collectionName}」'}',
                ),
              ),
            ),
          if (run.failed || run.cancelled)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: OutlinedButton.icon(
                onPressed: agent.busy ? null : () => agent.run(run.prompt),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新执行'),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> configureAgent(BuildContext context, AgentController agent) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AgentConfig(agent: agent),
    );

class _AgentConfig extends StatefulWidget {
  const _AgentConfig({required this.agent});
  final AgentController agent;
  @override
  State<_AgentConfig> createState() => _AgentConfigState();
}

class _AgentConfigState extends State<_AgentConfig> {
  late final TextEditingController _url, _model;
  final _key = TextEditingController();
  String? _presetId;
  String? _error;
  String _probe = '';
  bool _probeOk = false;
  bool _saving = false;
  bool _testing = false;
  ModelProvider? get _preset =>
      _presetId == null ? null : modelProviderById(_presetId!);
  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.agent.endpoint);
    _model = TextEditingController(text: widget.agent.model);
    _presetId = kModelProviders
        .where((p) => p.endpoint == widget.agent.endpoint)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _applyPreset(String? id) {
    final preset = id == null ? null : modelProviderById(id);
    setState(() {
      _presetId = id;
      _error = null;
      _probe = '';
      if (preset != null) {
        _url.text = preset.endpoint;
        if (!preset.models.contains(_model.text.trim())) {
          _model.text = preset.models.first;
        }
      }
    });
  }

  String _readable(Object error) => switch (error) {
    FormatException e => e.message,
    HttpException e => e.message,
    _ => error.toString(),
  };

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _probe = '';
      _error = null;
    });
    try {
      final message = await widget.agent.testModel(
        _url.text,
        _model.text,
        _key.text,
      );
      if (mounted) {
        setState(() {
          _probe = message;
          _probeOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _probe = _readable(e);
          _probeOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save({bool local = false}) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.agent.configure(
        local ? '' : _url.text,
        local ? '' : _model.text,
        _key.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('接入你的 AI 模型'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '支持 Chat Completions 兼容服务，包括开源模型与本机模型。可先选常用平台，也可只填域名——会自动补全 /v1/chat/completions。发送任务时，需求、偏好和影片摘要会发送到此服务。',
              style: WowType.body(12, color: WowColors.muted),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _presetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '常用平台（可选）'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('自定义 / 其他兼容服务'),
                ),
                for (final p in kModelProviders)
                  DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.label),
                  ),
              ],
              onChanged: _saving ? null : _applyPreset,
            ),
            if (_preset != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _preset!.note,
                  style: WowType.body(11, color: WowColors.muted),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              enabled: !_saving,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '接口地址（可只填域名）',
                hintText: 'api.deepseek.com 或 http://localhost:11434',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _model,
              enabled: !_saving,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '模型名称'),
            ),
            if (_preset != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in _preset!.models)
                    ChoiceChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: _model.text.trim() == m,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _model.text = m),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _key,
              enabled: !_saving,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '留空保留同一服务的密钥；本机服务可不填',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '密钥单独保存在系统凭据存储中，不写入任务记录。iOS 与 macOS 使用系统钥匙串；其他平台使用受限权限文件。',
              style: WowType.body(11, color: WowColors.muted),
            ),
            if (_probe.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _probeOk ? Icons.check_circle_outline : Icons.error_outline,
                      size: 15,
                      color: _probeOk ? WowColors.success : WowColors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _probe,
                        style: TextStyle(
                          fontSize: 12,
                          color: _probeOk ? WowColors.success : WowColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: WowColors.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => _save(local: true),
        child: const Text('使用本地规则'),
      ),
      TextButton(
        onPressed: _saving || _testing ? null : _test,
        child: _testing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('测试连接'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : () => _save(),
        child: const Text('保存配置'),
      ),
    ],
  );
}
