import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  final bool firstRun;
  const SettingsScreen({super.key, this.firstRun = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _password;
  late final TextEditingController _apiKey;
  late final TextEditingController _geminiApiKey;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _url = TextEditingController(text: state.api.baseUrl);
    _password = TextEditingController(text: state.api.password);
    _apiKey = TextEditingController(text: state.api.apiKey);
    _geminiApiKey = TextEditingController(text: state.api.geminiApiKey);
    if (state.api.configured && state.workspacesResponse == null) {
      Future.microtask(() => state.refreshWorkspaces());
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _password.dispose();
    _apiKey.dispose();
    _geminiApiKey.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final state = context.read<AppState>();
    setState(() => _testing = true);
    await state.saveSettings(
      baseUrl: _url.text,
      password: _password.text,
      newApiKey: _apiKey.text,
      newGeminiApiKey: _geminiApiKey.text,
    );
    try {
      await state.api.login();
      await state.refreshBooks();
      state.refreshPrompts();
      state.refreshModels();
      state.refreshWorkspaces();
      if (mounted) showSnack(context, 'Connected ✓');
    } catch (e) {
      if (mounted) showSnack(context, 'Connection failed: $e');
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _pickModel() async {
    final state = context.read<AppState>();
    if (state.models.isEmpty) await state.refreshModels();
    if (!mounted) return;
    final search = TextEditingController();
    final picked = await showModalBottomSheet<ModelInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = search.text.toLowerCase();
          final filtered = state.models
              .where((m) =>
                  m.name.toLowerCase().contains(q) ||
                  m.id.toLowerCase().contains(q))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setSheet(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search models…',
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final m = filtered[i];
                      final isGoogle = m.isGoogle;
                      final subtitle = [
                        m.id,
                        if (isGoogle) 'Direct Google' else 'OpenRouter',
                        if (m.context != null) '${(m.context! / 1024).round()}K context',
                      ].join(' · ');

                      return ListTile(
                        leading: Icon(isGoogle
                            ? Icons.auto_awesome
                            : Icons.psychology_outlined),
                        title: Text(m.name),
                        subtitle: Text(subtitle),
                        selected: m.id == state.model,
                        onTap: () => Navigator.pop(ctx, m),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (picked != null) await state.setModel(picked.id);
  }

  Future<void> _pickWorkspace() async {
    final state = context.read<AppState>();
    if (state.workspacesResponse == null) await state.refreshWorkspaces();
    if (!mounted) return;
    final resp = state.workspacesResponse;
    if (resp == null || resp.workspaces.isEmpty) {
      showSnack(context, 'No workspaces found.');
      return;
    }

    final picked = await showModalBottomSheet<WorkspaceInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Select Workspace / Database',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: resp.workspaces.length,
                itemBuilder: (ctx, i) {
                  final w = resp.workspaces[i];
                  final isCurrent = w.active ||
                      (state.activeWorkspace?.name == w.name &&
                          state.activeWorkspace?.owner == w.owner);
                  final subtitle = [
                    w.kind,
                    if (w.books > 0) '${w.books} books',
                    if (w.videos > 0) '${w.videos} videos',
                  ].join(' · ');

                  return ListTile(
                    leading: Icon(w.isCanon ? Icons.verified : Icons.folder_open),
                    title: Text(w.label),
                    subtitle: Text(subtitle),
                    selected: isCurrent,
                    trailing: isCurrent
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => Navigator.pop(ctx, w),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      try {
        await state.switchWorkspace(picked);
        if (mounted) showSnack(context, 'Switched to ${picked.label}');
      } catch (e) {
        if (mounted) showSnack(context, 'Failed to switch workspace: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activeWs = state.activeWorkspace?.label ?? 'Canon (default)';

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.firstRun) ...[
          Text('Welcome 👋',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
              "Point the app at your Phil's Library deployment. It uses the same database as the web version."),
          const SizedBox(height: 20),
        ],
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://your-space.hf.space',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'App password',
            helperText: 'Same password as the web login (APP_PASSWORD or member login).',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKey,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'OpenRouter API key (optional)',
            helperText:
                'Only needed if the server has no OPENROUTER_API_KEY secret. Stored on this device only.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _geminiApiKey,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Google Gemini API key (optional)',
            helperText:
                'Direct Google AI Studio key (bypasses OpenRouter for Google models with zero routing fee).',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _testing ? null : _saveAndTest,
          icon: _testing
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link),
          label: const Text('Save & test connection'),
        ),
        const Divider(height: 40),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Workspace / Database'),
          subtitle: Text(activeWs),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickWorkspace,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('Model'),
          subtitle: Text(state.model),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickModel,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: Text(
                    'Text size: ${(state.mdScale * 100).round()}%')),
            const TextSizeButtons(),
          ],
        ),
        const SizedBox(height: 8),
        Text('Temperature: ${state.temperature.toStringAsFixed(1)}'),
        Slider(
          value: state.temperature,
          min: 0,
          max: 1.5,
          divisions: 15,
          label: state.temperature.toStringAsFixed(1),
          onChanged: (v) => state.saveSettings(
            baseUrl: _url.text,
            password: _password.text,
            newApiKey: _apiKey.text,
            newGeminiApiKey: _geminiApiKey.text,
            newTemperature: v,
          ),
        ),
      ],
    );

    if (widget.firstRun) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setup')),
        body: SafeArea(child: body),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: body,
    );
  }
}
