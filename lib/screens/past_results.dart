import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
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
  // iPad share-sheet anchor, read before any await: touching the BuildContext
  // after an async gap throws if the widget was disposed meanwhile.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(markdown);
    // share_plus 13 replaced the static Share.shareXFiles() with
    // SharePlus.instance.share(ShareParams(...)).
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/markdown')],
      subject: filename,
      sharePositionOrigin: origin,
    ));
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
  final String? bookId;
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
    this.bookId,
    this.error,
    this.scopeLabel = 'this book',
    this.sourceTitle = '',
    this.sourceAuthor,
  });

  String get _sourceLine =>
      '$sourceTitle${(sourceAuthor ?? '').trim().isEmpty ? '' : ' — $sourceAuthor'} (book)';

  /// Erase all extracted results and knowledge graph entries for this book.
  Future<void> _eraseAllResultsAndGraph(BuildContext context) async {
    if (bookId == null || bookId!.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all results & graph?'),
        content: Text(
          'Are you sure you want to permanently erase all ${results.length} extracted result(s) and knowledge graph entries for "$sourceTitle" from the database?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase all'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final state = context.read<AppState>();
      await state.api.deleteBookResults(bookId!, includeGraph: true);
      if (context.mounted) {
        showSnack(context, 'All results and graph entries erased.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed to erase results: $e');
    }
  }

  Future<void> _deleteOneResult(BuildContext context, SavedResult r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved result?'),
        content: Text(
          'Are you sure you want to permanently delete "${r.promptName ?? 'this result'}" from the database?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final state = context.read<AppState>();
      await state.api.deleteResult(r.id);
      if (context.mounted) {
        showSnack(context, 'Result deleted.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed to delete: $e');
    }
  }

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
              if (results.isNotEmpty) ...[
                if (bookId != null && bookId!.isNotEmpty)
                  IconButton(
                    tooltip: 'Erase all results & graph',
                    icon: const Icon(Icons.delete_forever_outlined),
                    onPressed: loading ? null : () => _eraseAllResultsAndGraph(context),
                  ),
                IconButton(
                  tooltip: 'Share all results as one .md',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _exportAll(context),
                ),
              ],
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = results[i];
                      final meta = [
                        fmtWhen(r.createdAt),
                        if (r.scope != null && r.scope!.isNotEmpty) r.scope!,
                        if (r.model != null && r.model!.isNotEmpty) r.model!,
                        if (r.cost != null && r.cost!.isNotEmpty) r.cost!,
                      ].where((s) => s.isNotEmpty).join(' · ');
                      return ListTile(
                        leading: Icon(
                          r.hasAudio
                              ? Icons.audiotrack
                              : Icons.description_outlined,
                          color: r.hasAudio
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(r.promptName ?? 'Result',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: meta.isEmpty
                            ? null
                            : Text(meta,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (r.hasAudio)
                              Icon(Icons.download_for_offline_outlined,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'Delete result',
                              onPressed: () => _deleteOneResult(context, r),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final deleted = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => SavedResultPage(
                                    result: r,
                                    sourceTitle: sourceTitle,
                                    sourceLine: _sourceLine)),
                          );
                          if (deleted == true) onRefresh();
                        },
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

  Future<void> _exportAudio(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    showSnack(context, 'Fetching audio…');
    try {
      final state = context.read<AppState>();
      final bytes = await state.api.fetchResultAudioBytes(result.id);
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) showSnack(context, 'Audio data not found on server.');
        return;
      }
      final name = downloadName(
        title: sourceTitle.isEmpty ? 'Audio' : sourceTitle,
        kind: result.promptName ?? 'Narration',
        date: DateTime.tryParse(result.createdAt ?? ''),
        ext: 'mp3',
      );
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'audio/mpeg', name: name)],
        subject: '${sourceTitle.isEmpty ? 'Audio' : sourceTitle} — ${result.promptName ?? 'Narration'}',
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed to export audio: $e');
    }
  }

  Future<void> _deleteThisResult(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this result?'),
        content: Text(
          'Are you sure you want to permanently delete "${result.promptName ?? 'this result'}" from the database?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final state = context.read<AppState>();
      await state.api.deleteResult(result.id);
      if (context.mounted) {
        showSnack(context, 'Result deleted.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed to delete: $e');
    }
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
          if (result.hasAudio)
            IconButton(
              tooltip: 'Export Audio (.mp3)',
              icon: const Icon(Icons.audiotrack),
              onPressed: () => _exportAudio(context),
            ),
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
          IconButton(
            tooltip: 'Delete saved result',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteThisResult(context),
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
