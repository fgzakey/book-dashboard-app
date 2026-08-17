import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';
import 'book_detail_screen.dart';

class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = context.read<AppState>().bookQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addBook(BuildContext context) async {
    final state = context.read<AppState>();
    // file_picker 10 API. 11 made FilePicker static (FilePicker.pickFiles()),
    // but 11 breaks the Android build — see the pubspec note before changing.
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Uploading & parsing epub…\nThis can take a minute for big books.')),
          ],
        ),
      ),
    );
    try {
      final b = await state.addBookFromFile(file.bytes!, file.name);
      if (!context.mounted) return;
      Navigator.pop(context); // close progress dialog
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.bookId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shown = state.visibleBooks;
    final filtering = state.bookQuery.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(state.books.isEmpty
            ? 'Books'
            : filtering
                ? 'Books (${shown.length} / ${state.books.length})'
                : 'Books (${state.books.length})'),
        actions: [
          PopupMenuButton<BookSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Order by',
            initialValue: state.bookSort,
            onSelected: (s) => state.setBookSort(s),
            itemBuilder: (_) => [
              for (final s in BookSort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == state.bookSort,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: state.loadingBooks ? null : () => state.refreshBooks(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addBook(context),
        icon: const Icon(Icons.add),
        label: const Text('Add epub'),
      ),
      body: Builder(builder: (context) {
        if (state.loadingBooks && state.books.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.booksError != null && state.books.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load books:\n${state.booksError}',
                  textAlign: TextAlign.center),
            ),
          );
        }
        if (state.books.isEmpty) {
          return const Center(
            child: Text('No books yet.\nTap "Add epub" to upload one.',
                textAlign: TextAlign.center),
          );
        }
        return RefreshIndicator(
          onRefresh: () => state.refreshBooks(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search books by title or author…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: filtering
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              state.setBookQuery('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (q) => state.setBookQuery(q),
                ),
              ),
              if (filtering && shown.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No books match "${state.bookQuery.trim()}".',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final b = shown[i];
                      final stamp = sortStamp(b, state.bookSort);
                      final details = [
                        if (b.author != null && b.author!.isNotEmpty) b.author!,
                        '${b.wordCount} words',
                        if (b.chapters.isNotEmpty) '${b.chapters.length} chapters',
                        if (b.chat.isNotEmpty) '${b.chat.length ~/ 2} Q&A',
                        if (stamp.isNotEmpty) stamp,
                      ].join(' · ');

                      return ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(b.title ?? b.bookId,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(details),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete book?'),
                                content: Text(b.title ?? b.bookId),
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
                            if (ok == true) await state.deleteBook(b.bookId);
                          },
                        ),
                        onTap: () {
                          // Stamp last_opened_at fire-and-forget
                          state.api.touchBook(b.bookId).then((openedAt) {
                            if (openedAt != null) b.openedAt = openedAt;
                          }).catchError((_) {});

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BookDetailScreen(bookId: b.bookId)),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
