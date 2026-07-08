import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../scribe_svg.dart';

/// "Visual Scribe" — turns the book (or one chapter) into a hand-drawn board:
/// a whiteboard graphic recording, a memory palace, or a knowledge map, with
/// embedded AI-painted illustrations. Boards are saved into book.scribes with
/// the exact same record shape as the web app, so they sync both ways.
class ScribeTab extends StatefulWidget {
  final Book book;
  const ScribeTab({super.key, required this.book});

  @override
  State<ScribeTab> createState() => _ScribeTabState();
}

class _ScribeTabState extends State<ScribeTab> {
  String _scope = 'book'; // "book" | "ch-<idx>"
  bool _running = false;
  String _status = '';
  String? _error;
  late final TextEditingController _imageModelCtl;
  WebViewController? _web;
  String _loadedSvg = '';

  @override
  void initState() {
    super.initState();
    _imageModelCtl = TextEditingController(
        text: context.read<AppState>().scribeImageModel);
  }

  @override
  void dispose() {
    _imageModelCtl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _currentRec {
    final rec = widget.book.scribes?[_scope];
    return rec is Map ? Map<String, dynamic>.from(rec) : null;
  }

  String _scopeLabel(String key) {
    if (key == 'book') return 'Whole book';
    final i = int.tryParse(key.replaceFirst('ch-', '')) ?? -1;
    if (i < 0 || i >= widget.book.chapters.length) return key;
    return 'Ch. ${i + 1}: ${((widget.book.chapters[i] as Map)['title'] ?? '').toString()}';
  }

  String _sourceText() {
    if (_scope == 'book') return widget.book.text;
    final i = int.tryParse(_scope.replaceFirst('ch-', '')) ?? -1;
    return widget.book.chapterText(i);
  }

  Future<void> _run() async {
    final state = context.read<AppState>();
    final b = widget.book;
    setState(() => _error = null);
    final srcText = _sourceText().trim();
    if (srcText.isEmpty) {
      setState(() => _error = 'This scope has no text to work from.');
      return;
    }
    if (state.model.isEmpty) {
      setState(() => _error = 'Pick a model in Settings first.');
      return;
    }
    await state.setScribePrefs(imageModel: _imageModelCtl.text.trim());
    final scopeTitle = _scope == 'book'
        ? (b.title ?? 'Book')
        : '${b.title} — ${_scopeLabel(_scope)}';
    setState(() {
      _running = true;
      _status = 'Designing the board…';
    });
    try {
      // Step 1: design the spec only (fast) and render the vector board.
      final data = await state.api.scribeSpec(
        booktext: srcText,
        title: scopeTitle,
        author: b.author ?? '',
        textModel: state.model,
        mode: state.scribeMode,
        artStyle: state.scribeArtStyle,
        temperature: state.temperature,
      );
      final spec = Map<String, dynamic>.from(data['spec'] as Map);
      final usage = data['usage'] is Map
          ? Map<String, dynamic>.from(data['usage'])
          : null;
      final baseRec = <String, dynamic>{
        'spec': spec,
        'images': <dynamic>[],
        'imageErrors': <dynamic>[],
        'svg': buildScribeSvg(spec, []),
        'model': data['model'] ?? state.model,
        'imageModel': state.scribeImageModel,
        'mode': data['mode'] ?? state.scribeMode,
        'artStyle': data['artStyle'] ?? state.scribeArtStyle,
        'scope': _scope,
        'scopeLabel': _scopeLabel(_scope),
        'cost': formatUsageCost(usage),
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      b.scribes = {...?b.scribes, _scope: baseRec};
      setState(() {}); // board shows immediately
      await state.saveBook(b);

      // Step 2: paint illustrations — one short request each (long single
      // requests get killed by the Space proxy).
      final jobs = state.scribeGenImages
          ? ((spec['illustrations'] as List?) ?? [])
              .whereType<Map>()
              .where((j) => (j['prompt'] ?? '').toString().isNotEmpty)
              .take(3)
              .toList()
          : <Map>[];
      if (jobs.isNotEmpty) {
        final ctx = (spec['title'] ?? '').toString().isNotEmpty
            ? 'Illustration for "${spec['title']}"${(spec['subtitle'] ?? '').toString().isNotEmpty ? ' — ${spec['subtitle']}' : ''}. '
            : '';
        final images = <Map<String, dynamic>>[];
        final imageErrors = <String>[];
        for (var i = 0; i < jobs.length; i++) {
          if (mounted) {
            setState(() =>
                _status = 'Painting illustration ${i + 1} of ${jobs.length}…');
          }
          try {
            final url = await state.api.scribeImage(
              imagePrompt: jobs[i]['prompt'].toString(),
              imageContext: ctx,
              artStyle: state.scribeArtStyle,
              imageModel: state.scribeImageModel,
            );
            images.add({
              'role': (jobs[i]['role'] ?? (i == 0 ? 'hero' : 'spot')).toString(),
              'placement': (jobs[i]['placement'] ?? '').toString(),
              'url': url,
            });
          } catch (e) {
            imageErrors.add(e.toString());
          }
        }
        final fullRec = {
          ...baseRec,
          'images': images,
          'imageErrors': imageErrors,
          'svg': buildScribeSvg(spec, images),
        };
        b.scribes = {...?b.scribes, _scope: fullRec};
        setState(() {});
        await state.saveBook(b);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) {
      setState(() {
        _running = false;
        _status = '';
      });
    }
  }

  Future<void> _shareSvg(String svg, String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final file = File('${dir.path}/$safe.svg');
    await file.writeAsString(svg);
    await Share.shareXFiles([XFile(file.path, mimeType: 'image/svg+xml')],
        subject: name);
  }

  Future<void> _shareGraphJson(Map<String, dynamic> graph, String name) async {
    final dir = await getTemporaryDirectory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final file = File('${dir.path}/$safe-graph.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(graph));
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
        subject: '$name — knowledge graph');
  }

  Widget _board(String svg) {
    if (_web == null || _loadedSvg != svg) {
      _web ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF));
      _loadedSvg = svg;
      _web!.loadHtmlString(
          '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body{margin:0;padding:0;background:#fff}svg{width:100%;height:auto;display:block}</style></head><body>$svg</body></html>');
    }
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxWidth / 1.6; // board is 1600x1000
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
            width: c.maxWidth, height: h, child: WebViewWidget(controller: _web!)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final b = widget.book;
    final rec = _currentRec;
    final otherKeys = (b.scribes?.keys.where((k) => k != _scope) ?? const [])
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Turns this book (or one chapter) into a hand-drawn board — a whiteboard, a memory palace, or a knowledge map — with embedded AI-painted art. Your main model designs the board; an image model paints the art.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          // Keyed so programmatic scope changes (tapping "other boards")
          // rebuild the field — initialValue alone doesn't track state.
          key: ValueKey('scope-$_scope'),
          initialValue: _scope,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Scope', border: OutlineInputBorder(), isDense: true),
          items: [
            const DropdownMenuItem(value: 'book', child: Text('Whole book')),
            for (var i = 0; i < b.chapters.length; i++)
              DropdownMenuItem(
                value: 'ch-$i',
                child: Text(
                    'Ch. ${i + 1}: ${((b.chapters[i] as Map)['title'] ?? '').toString()}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            _scope = v ?? 'book';
            _web = null; // reload the board webview for the new scope
            _loadedSvg = '';
          }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: state.scribeMode,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Board mode',
              border: OutlineInputBorder(),
              isDense: true),
          items: scribeModes
              .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
              .toList(),
          onChanged: (v) => state.setScribePrefs(mode: v),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: state.scribeArtStyle,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Art style (for the illustrations)',
              border: OutlineInputBorder(),
              isDense: true),
          items: scribeArtStyles
              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
              .toList(),
          onChanged: (v) => state.setScribePrefs(artStyle: v),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _imageModelCtl,
          decoration: const InputDecoration(
            labelText: 'Image model (for the illustrations)',
            hintText: 'google/gemini-2.5-flash-image',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
              'Generate embedded AI illustration(s) — off for a faster, vector-only board'),
          value: state.scribeGenImages,
          onChanged: (v) => state.setScribePrefs(genImages: v),
        ),
        FilledButton.icon(
          icon: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.draw_outlined),
          label: Text(_running
              ? (_status.isEmpty ? 'Drawing the board…' : _status)
              : '${rec != null ? 'Re-draw' : 'Generate'} board'),
          onPressed: _running || b.text.isEmpty ? null : _run,
        ),
        if (b.text.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('The book text is still loading…'),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (rec != null) ...[
          const SizedBox(height: 14),
          Text(_scopeLabel(_scope),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '${scribeModes.where((m) => m.id == rec['mode']).firstOrNull?.name.split(' (').first ?? 'Whiteboard'}'
            ' by ${rec['model'] ?? ''}'
            '${(rec['images'] as List?)?.isNotEmpty == true ? ' · art by ${rec['imageModel'] ?? 'image model'} · ${(rec['images'] as List).length} illustration(s)' : ' · vector only'}'
            '${rec['cost'] != null ? ' · ${rec['cost']}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if ((rec['imageErrors'] as List?)?.isNotEmpty == true)
            Text('Illustration note: ${(rec['imageErrors'] as List).join('; ')}',
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _board((rec['svg'] ?? '').toString()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share SVG'),
                onPressed: () => _shareSvg((rec['svg'] ?? '').toString(),
                    '${b.title ?? 'book'}-$_scope'),
              ),
              if ((rec['spec'] as Map?)?['graph'] is Map)
                OutlinedButton.icon(
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('Graph JSON'),
                  onPressed: () => _shareGraphJson(
                      Map<String, dynamic>.from((rec['spec'] as Map)['graph']),
                      b.title ?? 'book'),
                ),
            ],
          ),
          if ((rec['spec'] as Map?)?['mermaid'] is String &&
              ((rec['spec'] as Map)['mermaid'] as String).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Mermaid diagram source',
                  style: TextStyle(fontSize: 14)),
              children: [
                SelectableText((rec['spec'] as Map)['mermaid'].toString()),
              ],
            ),
        ],
        if (otherKeys.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Other boards for this book (${otherKeys.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final k in otherKeys)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dashboard_outlined),
              title: Text(
                  ((b.scribes![k] as Map?)?['spec'] as Map?)?['title']?.toString() ??
                      _scopeLabel(k)),
              subtitle: Text(_scopeLabel(k)),
              trailing: IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _shareSvg(
                    ((b.scribes![k] as Map?)?['svg'] ?? '').toString(),
                    '${b.title ?? 'book'}-$k'),
              ),
              onTap: () => setState(() {
                _scope = k;
                _web = null;
                _loadedSvg = '';
              }),
            ),
        ],
      ],
    );
  }
}
