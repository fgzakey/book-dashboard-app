import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../md_zoom.dart';
import '../models.dart';
import 'images_tab.dart';
import 'scribe_tab.dart';

class BookDetailScreen extends StatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final _chatController = TextEditingController();
  bool _sending = false;
  bool _loadingFull = false;
  String _streaming = ''; // live assistant output while a reply streams in

  @override
  void initState() {
    super.initState();
    // The library list rows are light — fetch the full record once on open
    // (text, segments, images, scribes).
    Future.microtask(_ensureFull);
  }

  Future<void> _ensureFull() async {
    final state = context.read<AppState>();
    final b = _book(state);
    if (b == null || b.fullLoaded) return;
    setState(() => _loadingFull = true);
    try {
      await state.ensureFullBook(b);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not load the full book: $e');
    }
    if (mounted) setState(() => _loadingFull = false);
  }

  Book? _book(AppState state) {
    try {
      return state.books.firstWhere((b) => b.bookId == widget.bookId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _send(AppState state, Book b) async {
    final q = _chatController.text.trim();
    if (q.isEmpty || _sending) return;
    if (b.text.isEmpty) {
      showSnack(context, 'Book text is still loading — try again in a moment.');
      return;
    }
    setState(() {
      _sending = true;
      _streaming = '';
      b.chat.add(ChatMessage(role: 'user', content: q));
      _chatController.clear();
    });
    try {
      final resp = await state.askBook(b, b.chat, onDelta: (d) {
        if (mounted) setState(() => _streaming += d);
      });
      b.chat.add(ChatMessage(
        role: 'assistant',
        content: resp.content,
        model: resp.model,
        cost: resp.cost,
      ));
      await state.saveBook(b); // persist chat to the shared DB
    } catch (e) {
      if (mounted) showSnack(context, 'Chat failed: $e');
      b.chat.removeLast(); // roll back the user message
    }
    if (mounted) {
      setState(() {
        _sending = false;
        _streaming = '';
      });
    }
  }

  Future<void> _runPrompt(AppState state, Book b) async {
    if (b.text.isEmpty) {
      showSnack(context, 'Book text is still loading — try again in a moment.');
      return;
    }
    if (state.prompts.isEmpty) await state.refreshPrompts();
    if (!mounted) return;
    final prompt = await showModalBottomSheet<PromptTemplate>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Run a standardized prompt',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...state.prompts.map((p) => ListTile(
                leading: Icon(p.builtin ? Icons.star_outline : Icons.edit_note),
                title: Text(p.name),
                subtitle: Text(p.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, p),
              )),
        ],
      ),
    );
    if (prompt == null || !mounted) return;

    // Scope: whole book, or a subset of chapters (same as the web's
    // "Choose chapters" — for big books that overflow the model's context).
    List<int>? scope;
    if (b.chapters.isNotEmpty) {
      scope = await _pickChapterScope(b);
      if (scope == null && !mounted) return;
      if (scope != null && scope.isEmpty) return; // cancelled
    }
    if (!mounted) return;
    final scopeLabel = scope == null
        ? 'whole book'
        : 'chapters ${scope.map((i) => i + 1).join(', ')}';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: _StreamingResultViewer(
          title: prompt.name,
          run: (onDelta) => context
              .read<AppState>()
              .runPrompt(b, prompt, chapterScope: scope, onDelta: onDelta),
          onSave: (resp) async {
            await state.api.saveResult(
              content: resp.content,
              bookId: b.bookId,
              bookTitle: b.title,
              promptName: prompt.name,
              scope: scopeLabel,
              model: resp.model,
              cost: resp.cost,
            );
          },
        ),
      ),
    );
  }

  /// Returns null = whole book, [] = cancelled, otherwise chapter indexes.
  Future<List<int>?> _pickChapterScope(Book b) async {
    final selected = <int>{};
    final result = await showModalBottomSheet<List<int>?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              const Text('Scope',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('Whole book'),
                onTap: () => Navigator.pop(ctx, null),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: b.chapters.length,
                  itemBuilder: (ctx, i) => CheckboxListTile(
                    dense: true,
                    value: selected.contains(i),
                    title: Text(
                        'Ch. ${i + 1}: ${((b.chapters[i] as Map)['title'] ?? '').toString()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onChanged: (v) => setSheet(() =>
                        v == true ? selected.add(i) : selected.remove(i)),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, (selected.toList()..sort())),
                    child: Text(selected.isEmpty
                        ? 'Select chapters (or tap Whole book)'
                        : 'Run on ${selected.length} chapter(s)'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Distinguish "picked whole book" (null) from "dismissed the sheet":
    // both come back null, which is fine — whole book is the sensible default.
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final b = _book(state);
    if (b == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Book not found.')),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(b.title ?? b.bookId,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chat'),
            Tab(text: 'Chapters'),
            Tab(text: 'Text'),
            Tab(text: 'Images'),
            Tab(text: 'Scribe'),
          ]),
          actions: [
            const TextSizeButtons(),
            IconButton(
              tooltip: 'Run prompt',
              icon: const Icon(Icons.bolt),
              onPressed: () => _runPrompt(state, b),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_loadingFull) const LinearProgressIndicator(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildChat(state, b),
                  _buildChapters(b),
                  _buildText(b),
                  ImagesTab(book: b),
                  ScribeTab(book: b),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(AppState state, Book b) {
    final showStream = _sending && _streaming.isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: b.chat.isEmpty && !showStream
              ? const Center(child: Text('Ask anything about this book.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: b.chat.length + (showStream ? 1 : 0),
                  itemBuilder: (context, i) {
                    final streamingBubble = showStream && i == b.chat.length;
                    final m = streamingBubble
                        ? ChatMessage(role: 'assistant', content: _streaming)
                        : b.chat[i];
                    final isUser = m.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isUser
                            ? Text(m.content)
                            : ZoomMd(data: m.content),
                      ),
                    );
                  },
                ),
        ),
        if (_sending) const LinearProgressIndicator(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Ask about the book…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(state, b),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : () => _send(state, b),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChapters(Book b) {
    if (b.chapters.isEmpty) {
      return const Center(child: Text('No chapters detected in this epub.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: b.chapters.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = Map<String, dynamic>.from(b.chapters[i]);
        final title = c['title']?.toString() ?? 'Chapter ${i + 1}';
        final words = (c['wordCount'] as num?)?.toInt() ?? 0;
        final summary = c['summary']?.toString() ?? '';
        return ListTile(
          leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
          title: Text(title),
          subtitle: Text(
            [
              '$words words',
              if (summary.isNotEmpty) summary,
            ].join(' — '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: const [TextSizeButtons(), SizedBox(width: 4)],
                ),
                // Rendered as Markdown (nice typography), not raw text.
                body: Markdown(
                  data: b.chapterText(i),
                  selectable: true,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildText(Book b) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('${b.wordCount} words')),
              if (b.language != null && b.language!.isNotEmpty)
                Chip(label: Text(b.language!)),
              if (b.chapters.isNotEmpty)
                Chip(label: Text('${b.chapters.length} chapters')),
              ActionChip(
                avatar: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: b.text));
                  showSnack(context, 'Book text copied.');
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (b.text.isEmpty)
            const Text('Loading the full book text…')
          else
            SelectableText(b.text),
        ],
      ),
    );
  }
}

/// Runs a prompt with live streaming output, then offers Copy / Save.
class _StreamingResultViewer extends StatefulWidget {
  final String title;
  final Future<ChatResponse> Function(void Function(String delta) onDelta) run;
  final Future<void> Function(ChatResponse resp) onSave;

  const _StreamingResultViewer(
      {required this.title, required this.run, required this.onSave});

  @override
  State<_StreamingResultViewer> createState() => _StreamingResultViewerState();
}

class _StreamingResultViewerState extends State<_StreamingResultViewer> {
  String _content = '';
  ChatResponse? _done;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final resp = await widget.run((d) {
        if (mounted) setState(() => _content += d);
      });
      if (mounted) {
        setState(() {
          _done = resp;
          _content = resp.content;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _done == null && _error == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          const TextSizeButtons(),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: _content.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _content));
                    showSnack(context, 'Copied.');
                  },
          ),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save'),
            onPressed: _done == null || _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await widget.onSave(_done!);
                      if (context.mounted) {
                        Navigator.pop(context);
                        showSnack(context, 'Saved to Results.');
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _saving = false);
                        showSnack(context, 'Save failed: $e');
                      }
                    }
                  },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (running) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _content.isEmpty && running
                ? const Center(child: Text('Waiting for the model…'))
                : ZoomMd(data: _content, scrollable: true),
          ),
        ],
      ),
    );
  }
}
