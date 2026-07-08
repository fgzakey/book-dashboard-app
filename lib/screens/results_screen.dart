import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  List<SavedResult> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await context
          .read<AppState>()
          .api
          .listResults(query: _search.text.trim());
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved results'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search title, prompt, or content…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(child: Text('Error: $_error'))
                : _results.isEmpty && !_loading
                    ? const Center(child: Text('No saved results.'))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(r.promptName ?? 'Result',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (r.bookTitle != null) r.bookTitle!,
                                if (r.model != null) r.model!,
                                if (r.cost != null) r.cost!,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => _ResultDetail(result: r)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ResultDetail extends StatelessWidget {
  final SavedResult result;
  const _ResultDetail({required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(result.promptName ?? 'Result',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
          if (result.bookTitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(result.bookTitle!,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          Expanded(child: Markdown(data: result.content, selectable: true)),
        ],
      ),
    );
  }
}
