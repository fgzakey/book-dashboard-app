import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../main.dart';
import '../models.dart';

/// "Images & Figures" — every image found inside the epub, mapped to the
/// chapter where it appears. AI describe titles each image, transcribes any
/// text in it and explains what it shows; export as Markdown or a PDF report.
class ImagesTab extends StatefulWidget {
  final Book book;
  const ImagesTab({super.key, required this.book});

  @override
  State<ImagesTab> createState() => _ImagesTabState();
}

class _ImagesTabState extends State<ImagesTab> {
  bool _describing = false;
  bool _upscaling = false;
  bool _pdfMaking = false;
  String _status = '';
  String? _error;

  List<Map<String, dynamic>> get _images => (widget.book.images ?? [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();

  String _chapterTitle(Map<String, dynamic> img) {
    final idx = widget.book.imageChapterIdx(img);
    if (idx == null) return 'Unplaced images';
    final t = ((widget.book.chapters[idx] as Map)['title'] ?? '').toString();
    return 'Ch. ${idx + 1}: $t';
  }

  /// Images grouped by chapter, in chapter order (unplaced last).
  List<MapEntry<String, List<Map<String, dynamic>>>> get _groups {
    final map = <String, List<Map<String, dynamic>>>{};
    final imgs = _images;
    imgs.sort((a, b) => (widget.book.imageChapterIdx(a) ?? 1 << 20)
        .compareTo(widget.book.imageChapterIdx(b) ?? 1 << 20));
    for (final im in imgs) {
      map.putIfAbsent(_chapterTitle(im), () => []).add(im);
    }
    return map.entries.toList();
  }

  Uint8List? _bytes(String? dataUrl) {
    if (dataUrl == null || !dataUrl.startsWith('data:image/')) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Future<void> _describe() async {
    final state = context.read<AppState>();
    final model = state.imagesModel;
    if (model.isEmpty) {
      showSnack(context, 'Pick a vision model first.');
      return;
    }
    final imgs = _images
        .where((im) => (im['dataUrl'] ?? '').toString().startsWith('data:image/'))
        .toList();
    if (imgs.isEmpty) return;
    setState(() {
      _describing = true;
      _error = null;
    });
    double cost = 0;
    final errors = <String>[];
    try {
      // One request per batch of 8 (matches the server's internal batch size)
      // so each call stays under the Space's proxy timeout.
      for (var off = 0; off < imgs.length; off += 8) {
        final batch = imgs.skip(off).take(8).toList();
        setState(() => _status =
            'Describing ${off + 1}–${off + batch.length} of ${imgs.length}…');
        final j = await state.api.describeImages(
          images: batch
              .map((im) => {
                    'id': im['id'],
                    'dataUrl': im['dataUrl'],
                    'chapterTitle': _chapterTitle(im),
                  })
              .toList(),
          model: model,
          title: widget.book.title,
          author: widget.book.author,
        );
        for (final e in (j['entries'] as List? ?? [])) {
          final entry = Map<String, dynamic>.from(e);
          final target = widget.book.images!
              .whereType<Map>()
              .cast<Map>()
              .where((im) => im['id'] == entry['id'])
              .firstOrNull;
          if (target == null) continue;
          target['title'] = entry['title'];
          target['type'] = entry['type'];
          target['text'] = entry['text'];
          target['description'] = entry['description'];
        }
        final u = j['usage'];
        if (u is Map && u['cost'] is num) cost += (u['cost'] as num).toDouble();
        for (final err in (j['errors'] as List? ?? [])) {
          errors.add(err.toString());
        }
      }
      widget.book.imagesMeta = {
        'model': model,
        'cost': cost > 0 ? formatUsageCost({'cost': cost}) : null,
        'at': DateTime.now().millisecondsSinceEpoch,
      };
      await state.saveBook(widget.book);
      if (mounted && errors.isNotEmpty) {
        setState(() => _error = errors.join('; '));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) {
      setState(() {
        _describing = false;
        _status = '';
      });
    }
  }

  Future<void> _upscale() async {
    final state = context.read<AppState>();
    final imgs = _images;
    if (imgs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI upscale all images?'),
        content: Text(
            'Regenerates each of the ${imgs.length} images ~2x sharper with the image model. AI upscaling can subtly alter small text.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upscale')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _upscaling = true;
      _error = null;
    });
    var done = 0;
    final errors = <String>[];
    for (final im in widget.book.images!.whereType<Map>()) {
      final dataUrl = (im['dataUrl'] ?? '').toString();
      if (!dataUrl.startsWith('data:image/')) continue;
      done++;
      if (mounted) setState(() => _status = 'Upscaling $done of ${imgs.length}…');
      try {
        im['dataUrl'] = await state.api
            .upscaleImage(dataUrl, imageModel: state.scribeImageModel);
      } catch (e) {
        errors.add('${im['name'] ?? im['id']}: $e');
      }
    }
    try {
      await state.saveBook(widget.book);
    } catch (e) {
      errors.add('Save failed: $e');
    }
    if (mounted) {
      setState(() {
        _upscaling = false;
        _status = '';
        _error = errors.isEmpty ? null : errors.join('; ');
      });
    }
  }

  String _markdown() {
    final b = widget.book;
    final buf = StringBuffer('# ${b.title ?? 'Book'} — Images & Figures\n');
    if ((b.author ?? '').isNotEmpty) buf.write('by ${b.author}\n');
    for (final g in _groups) {
      buf.write('\n## ${g.key}\n');
      for (final im in g.value) {
        final t = (im['title'] ?? im['name'] ?? 'Image').toString();
        final type = (im['type'] ?? '').toString();
        buf.write('\n### $t${type.isNotEmpty ? ' ($type)' : ''}\n');
        final text = (im['text'] ?? '').toString();
        if (text.isNotEmpty) buf.write('\n> $text\n');
        final desc = (im['description'] ?? '').toString();
        if (desc.isNotEmpty) buf.write('\n$desc\n');
      }
    }
    return buf.toString();
  }

  Future<void> _downloadPdf() async {
    final state = context.read<AppState>();
    setState(() {
      _pdfMaking = true;
      _error = null;
    });
    try {
      final items = <Map<String, dynamic>>[];
      for (final g in _groups) {
        for (final im in g.value) {
          items.add({
            'chapterTitle': g.key,
            'name': im['name'],
            'title': im['title'],
            'type': im['type'],
            'text': im['text'],
            'description': im['description'],
            'dataUrl': im['dataUrl'],
          });
        }
      }
      final bytes = await state.api.imagesPdf(
        title: widget.book.title ?? 'Book',
        author: widget.book.author,
        model: widget.book.imagesMeta?['model']?.toString(),
        items: items,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${(widget.book.title ?? 'book').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}-images.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: '${widget.book.title} — Images & Figures');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _pdfMaking = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final b = widget.book;
    final imgs = _images;
    final busy = _describing || _upscaling || _pdfMaking;
    final visionModels = state.visionModels;
    final hasDescriptions =
        imgs.any((im) => (im['description'] ?? '').toString().isNotEmpty);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Every image found inside the epub, mapped to the chapter where it appears. AI describe titles each image, transcribes any text in it, and explains what it shows.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: visionModels.any((m) => m.id == state.imagesModel)
              ? state.imagesModel
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Vision model (for AI describe)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: visionModels
              .map((m) => DropdownMenuItem(
                  value: m.id,
                  child: Text(m.name, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => v == null ? null : state.setImagesModel(v),
        ),
        if (visionModels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'No vision-capable models loaded yet — open Settings and refresh the model list.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(_describing
                  ? (_status.isEmpty ? 'Describing…' : _status)
                  : (hasDescriptions ? 'Re-describe (AI)' : 'AI describe images')),
              onPressed: busy || imgs.isEmpty ? null : _describe,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.hd_outlined, size: 18),
              label: Text(_upscaling
                  ? (_status.isEmpty ? 'Upscaling…' : _status)
                  : 'AI upscale'),
              onPressed: busy || imgs.isEmpty ? null : _upscale,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy .md'),
              onPressed: imgs.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _markdown()));
                      showSnack(context, 'Markdown catalog copied.');
                    },
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_pdfMaking ? 'Building PDF…' : 'PDF report'),
              onPressed: busy || imgs.isEmpty ? null : _downloadPdf,
            ),
          ],
        ),
        if (busy) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        Text(
          '${imgs.length} image${imgs.length == 1 ? '' : 's'}'
          '${b.cover != null ? ' + cover' : ''}'
          '${b.imagesMeta?['model'] != null ? ' · described by ${b.imagesMeta!['model']}' : ''}'
          '${b.imagesMeta?['cost'] != null ? ' · ${b.imagesMeta!['cost']}' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (b.cover != null && _bytes(b.cover) != null) ...[
          const SizedBox(height: 10),
          _ImageCard(
            bytes: _bytes(b.cover)!,
            title: 'Cover',
            subtitle: '${b.title ?? ''}${(b.author ?? '').isNotEmpty ? ' — ${b.author}' : ''}',
          ),
        ],
        if (imgs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('No images were found inside this epub (beyond the cover, if any).'),
          ),
        for (final g in _groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text('${g.key}  (${g.value.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ),
          for (final im in g.value)
            if (_bytes(im['dataUrl']?.toString()) != null)
              _ImageCard(
                bytes: _bytes(im['dataUrl'].toString())!,
                title: (im['title'] ?? im['name'] ?? 'Image').toString(),
                badge: (im['type'] ?? '').toString(),
                subtitle: [
                  (im['name'] ?? '').toString(),
                  if (im['bytes'] is num)
                    '${((im['bytes'] as num) / 1024).round()} KB',
                ].where((s) => s.isNotEmpty).join(' · '),
                text: (im['text'] ?? '').toString(),
                description: (im['description'] ?? '').toString(),
              ),
        ],
      ],
    );
  }
}

class _ImageCard extends StatelessWidget {
  final Uint8List bytes;
  final String title;
  final String? badge;
  final String? subtitle;
  final String? text;
  final String? description;

  const _ImageCard({
    required this.bytes,
    required this.title,
    this.badge,
    this.subtitle,
    this.text,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 560; // tablet: image beside text
          final image = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                      maxScale: 6, child: Image.memory(bytes)),
                ),
              ),
              child: Image.memory(bytes,
                  width: wide ? 240 : double.infinity, fit: BoxFit.contain),
            ),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  if ((badge ?? '').isNotEmpty)
                    Chip(
                        label: Text(badge!),
                        visualDensity: VisualDensity.compact),
                ],
              ),
              if ((subtitle ?? '').isNotEmpty)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              if ((text ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Text in image',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
                SelectableText(text!),
              ],
              if ((description ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(description!),
              ],
            ],
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                image,
                const SizedBox(width: 12),
                Expanded(child: info),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [image, const SizedBox(height: 8), info],
          );
        }),
      ),
    );
  }
}
