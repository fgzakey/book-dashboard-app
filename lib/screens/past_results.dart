import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../md_toc.dart';
import '../md_toc_view.dart';
import '../models.dart';

/// One saved result as the snake_case row shape [allResultsMd] and
/// [newestDate] expect — the same keys the API returns.
Map<String, dynamic> resultRow(SavedResult r) => {
      'prompt_name': r.promptName,
      'created_at': r.createdAt,
        'scope': r.scope,
      'model': r.model,
      'cost': r.cost,
      'content': r.content,
    };

/// Write a packaged .md to a temp file and hand it to the share sheet — the
/// app's equivalent of the dashboard's download button.
Future<void> shareMarkdown(
    BuildContext context, String markdown, String filename) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(markdown);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/markdown')],
        subject: filename);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not export: $e');
  }
}

/// Human-friendly local timestamp for a Postgres `created_at` string.
String fmtWhen(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// Order saved results exactly the way the web dashboard does
/// (`sortByPromptOrder` in app/page.js + app/videos-app.js): by position in
/// the BUILT-IN prompt list — Master Prompt (Adler Edition) first — then, for
/// anything not from a built-in prompt (custom prompts, "Images & Figures",
/// "Slides & Visuals"), oldest first at the end.
///
/// [builtins] must be the raw defaults from /api/prompts/defaults, NOT the
/// merged prompt list: editing a built-in stores it as a DB prompt, which the
/// merge appends at the end — ranking against that would sink the Adler
/// prompt to the bottom.
///
/// Saved names carry a language tag ("… (Spanish)"), hence the `startsWith`.
List<SavedResult> sortByPromptOrder(
    List<SavedResult> results, List<PromptTemplate> builtins) {
  int idx(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 999;
    for (var i = 0; i < builtins.length; i++) {
      final p = builtins[i].name.trim();
      if (p.isEmpty) continue;
      if (n == p || n.startsWith('$p (')) return i;
    }
    return 999;
  }

  DateTime when(SavedResult r) =>
      DateTime.tryParse(r.createdAt ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  final sorted = [...results];
  sorted.sort((a, b) {
    final d = idx(a.promptName) - idx(b.promptName);
    if (d != 0) return d;
    return when(a).compareTo(when(b)); // oldest first, same as the web
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
  // Identity of the book these results belong to — used for the export
  // filename and the provenance block, exactly as the dashboard does it.
  final String sourceTitle;
  final String? sourceAuthor;

  const PastResultsTab({
    super.key,
    required this.results,
    required this.loading,
    required this.onRefresh,
    this.error,
    this.scopeLabel = 'this book',
    this.sourceTitle = '',
    this.sourceAuthor,
  });

  String get _sourceLine =>
      '$sourceTitle${(sourceAuthor ?? '').trim().isEmpty ? '' : ' — $sourceAuthor'} (book)';

  /// All results for this book as one document, ordered as shown — the
  /// dashboard's "⬇ All results .md".
  Future<void> _exportAll(BuildContext context) async {
    final rows = results.map(resultRow).toList();
    final md = packageMd(
      allResultsMd(rows, title: sourceTitle),
      title: '$sourceTitle — Extracted knowledge & wisdom',
      models: [for (final r in results) r.model ?? ''],
      sources: [_sourceLine],
      kind: 'All prompt results',
    );
    await shareMarkdown(
      context,
      md,
      downloadName(
          title: sourceTitle.isEmpty ? 'Book' : sourceTitle,
          kind: 'All Results',
          date: newestDate(rows),
          ext: 'md'),
    );
  }

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
              if (results.isNotEmpty)
                IconButton(
                  tooltip: 'Share all results as one .md',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _exportAll(context),
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
                              builder: (_) => SavedResultPage(
                                  result: r,
                                  sourceTitle: sourceTitle,
                                  sourceLine: _sourceLine)),
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
  final String sourceTitle;
  final String sourceLine;
  const SavedResultPage({
    super.key,
    required this.result,
    this.sourceTitle = '',
    this.sourceLine = '',
  });

  /// This one result, packaged like the dashboard's per-result "⬇ .md".
  Future<void> _export(BuildContext context) async {
    final name = result.promptName ?? 'Result';
    final md = packageMd(
      result.content,
      title: '${sourceTitle.isEmpty ? 'Book' : sourceTitle} — $name',
      models: [result.model ?? ''],
      sources: [sourceLine],
      kind: 'Prompt result: $name',
    );
    await shareMarkdown(
      context,
      md,
      downloadName(
          title: sourceTitle.isEmpty ? name : sourceTitle,
          kind: name,
          date: DateTime.tryParse(result.createdAt ?? ''),
          ext: 'md'),
    );
  }

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
            tooltip: 'Share as .md (with contents + provenance)',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _export(context),
          ),
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
