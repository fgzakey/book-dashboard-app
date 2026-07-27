import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../md_toc_view.dart';
import '../models.dart';

/// Human-friendly local timestamp for a Postgres `created_at` string.
String fmtWhen(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// "Past results for this book" — the same saved results as the global
/// Results section, filtered to one book and shown at the top of its Chat
/// tab. Mirrors the web dashboard's layout convention (past results first,
/// generation controls below). Collapsed by default so chat stays the focus.
class PastResultsPanel extends StatelessWidget {
  final List<SavedResult> results;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String scopeLabel; // e.g. 'this book'

  const PastResultsPanel({
    super.key,
    required this.results,
    required this.loading,
    required this.onRefresh,
    this.error,
    this.scopeLabel = 'this book',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          loading && results.isEmpty
              ? 'Past results for $scopeLabel…'
              : 'Past results for $scopeLabel (${results.length})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: error != null
            ? Text(error!,
                style: TextStyle(color: scheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis)
            : null,
        children: [
          if (loading) const LinearProgressIndicator(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: results.isEmpty
                ? const ListTile(
                    dense: true,
                    title: Text(
                        'No saved results yet — run a prompt with the ⚡ button, then Save.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final meta = [
                        fmtWhen(r.createdAt),
                        if (r.scope != null && r.scope!.isNotEmpty) r.scope!,
                        if (r.model != null && r.model!.isNotEmpty) r.model!,
                        if (r.cost != null && r.cost!.isNotEmpty) r.cost!,
                      ].where((s) => s.isNotEmpty).join(' · ');
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(r.promptName ?? 'Result',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: meta.isEmpty
                            ? null
                            : Text(meta,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SavedResultPage(result: r)),
                        ),
                      );
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload'),
              onPressed: loading ? null : () => onRefresh(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen reader for one saved result (Markdown + bidirectional TOC).
class SavedResultPage extends StatelessWidget {
  final SavedResult result;
  const SavedResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final meta = [
      fmtWhen(result.createdAt),
      if (result.scope != null && result.scope!.isNotEmpty) result.scope!,
      if (result.model != null && result.model!.isNotEmpty) result.model!,
      if (result.cost != null && result.cost!.isNotEmpty) result.cost!,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(result.promptName ?? 'Result',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const TextSizeButtons(),
          IconButton(
            tooltip: 'Copy Markdown',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.content));
              showSnack(context, 'Copied.');
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(meta, style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(child: MdWithToc(data: result.content)),
        ],
      ),
    );
  }
}
