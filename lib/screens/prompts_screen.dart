import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';

class PromptsScreen extends StatelessWidget {
  const PromptsScreen({super.key});

  Future<void> _edit(BuildContext context, PromptTemplate? existing) async {
    final state = context.read<AppState>();
    final isNew = existing == null;
    final p = existing ??
        PromptTemplate(
          id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          template:
              'Book title: {{title}}\nAuthor: {{author}}\n\nBOOK TEXT:\n{{booktext}}',
        );

    final name = TextEditingController(text: p.name);
    final desc = TextEditingController(text: p.description);
    final tmpl = TextEditingController(text: p.template);

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(isNew ? 'New prompt' : 'Edit prompt'),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx, false)),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: desc,
                  decoration: const InputDecoration(
                      labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: tmpl,
                minLines: 12,
                maxLines: 30,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Template',
                  helperText:
                      'Use {{title}}, {{author}} and {{booktext}} as placeholders.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (save == true) {
      if (name.text.trim().isEmpty) {
        if (context.mounted) showSnack(context, 'Name is required.');
        return;
      }
      // Saving a builtin creates a DB override with the same id (like the web).
      await state.savePrompt(PromptTemplate(
        id: p.id,
        name: name.text.trim(),
        description: desc.text.trim(),
        template: tmpl.text,
      ));
      if (context.mounted) showSnack(context, 'Prompt saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Standardized prompts'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => state.refreshPrompts()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New prompt'),
      ),
      body: state.prompts.isEmpty
          ? const Center(child: Text('No prompts loaded yet. Pull refresh.'))
          : ListView.separated(
              itemCount: state.prompts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = state.prompts[i];
                return ListTile(
                  leading: Icon(p.builtin ? Icons.star_outline : Icons.edit_note),
                  title: Text(p.name),
                  subtitle: Text(p.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: p.builtin
                      ? const Tooltip(
                          message: 'Built-in', child: Icon(Icons.lock_outline, size: 18))
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete prompt?'),
                                content: Text(p.name),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) await state.deletePrompt(p.id);
                          },
                        ),
                  onTap: () => _edit(context, p),
                );
              },
            ),
    );
  }
}
