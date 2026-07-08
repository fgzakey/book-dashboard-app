import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import 'book_detail_screen.dart';

class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  Future<void> _addBook(BuildContext context) async {
    final state = context.read<AppState>();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Books'),
        actions: [
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
          child: ListView.separated(
            itemCount: state.books.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final b = state.books[i];
              return ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(b.title ?? b.bookId,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (b.author != null && b.author!.isNotEmpty) b.author!,
                    '${b.wordCount} words',
                    if (b.chapters.isNotEmpty) '${b.chapters.length} chapters',
                    if (b.chat.isNotEmpty) '${b.chat.length ~/ 2} Q&A',
                  ].join(' · '),
                ),
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BookDetailScreen(bookId: b.bookId)),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
