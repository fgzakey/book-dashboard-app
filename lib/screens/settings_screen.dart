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
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _url = TextEditingController(text: state.api.baseUrl);
    _password = TextEditingController(text: state.api.password);
    _apiKey = TextEditingController(text: state.api.apiKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _password.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final state = context.read<AppState>();
    setState(() => _testing = true);
    await state.saveSettings(
        baseUrl: _url.text, password: _password.text, newApiKey: _apiKey.text);
    try {
      await state.api.login();
      await state.refreshBooks();
      state.refreshPrompts();
      state.refreshModels();
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
                      return ListTile(
                        title: Text(m.name),
                        subtitle: Text(m.id),
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.firstRun) ...[
          Text('Welcome 👋',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text(
              'Point the app at your Book Dashboard deployment. It uses the same database as the web version.'),
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
            helperText: 'Same password as the web login (APP_PASSWORD).',
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
