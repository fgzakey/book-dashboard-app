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

/// Order saved results the way the Prompts list is ordered — built-ins first
/// (Master Prompt (Adler Edition) at the top), then custom prompts; anything
/// whose prompt is no longer in the list falls to the end. Within one prompt,
/// newest first.
///
/// Saved names carry a language tag ("… (Spanish)"), so a result is matched to
/// its prompt by exact name first, then by the longest name it starts with.
List<SavedResult> sortByPromptOrder(
    List<SavedResult> results, List<PromptTemplate> prompts) {
  const unknown = 1 << 30;

  int rankOf(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return unknown;
    var best = unknown;
    var bestLen = -1;
    for (var i = 0; i < prompts.length; i++) {
      final pn = prompts[i].name.trim();
      if (pn.isEmpty) continue;
      if (n == pn) return i;
      if (n.startsWith(pn) && pn.length > bestLen) {
        best = i;
        bestLen = pn.length;
      }
    }
    return best;
  }

  DateTime when(SavedResult r) =>
      DateTime.tryParse(r.createdAt ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  final sorted = [...results];
  sorted.sort((a, b) {
    final ra = rankOf(a.promptName);
    final rb = rankOf(b.promptName);
    if (ra != rb) return ra.compareTo(rb);
    return when(b).compareTo(when(a));
  });
  return sorted;
}

/// The **Results** tab of a single book — the same saved results as the
/// global Results section, filtered to this book. Sits between Chapters
/// and the Text tab, mirroring the web dashboard's "Past results for
/// this book".
class PastResultsTab extends StatelessWidget {
  final List<SavedResult> results;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String scopeLabel; // e.g. 'this book'

  const PastResultsTab({
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  loading && results.isEmpty
                      ? 'Loading saved results…'
                      : results.isEmpty
                          ? 'No saved results for $scopeLabel yet.'
                          : '${results.length} saved result${results.length == 1 ? '' : 's'} for $scopeLabel — in Prompts order, tap one to read',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh),
                onPressed: loading ? null : () => onRefresh(),
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(error!, style: TextStyle(color: scheme.error)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: results.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Run a standardized prompt with the ⚡ button, then Save — '
                          'every saved result for book shows up here and in the global Results section.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
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
                        leading: const Icon(Icons.description_outlined),
                        title: Text(r.promptName ?? 'Result',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: meta.isEmpty
                            ? null
                            : Text(meta,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SavedResultPage(result: r)),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
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
