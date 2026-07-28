import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'md_toc.dart';

/// Markdown viewer with a bidirectional table of contents — the Dart
/// counterpart of the web dashboard's MdWithToc (app/md-toc.js).
///
/// The document is split at H1–H4 boundaries ([splitSections]); each slice is
/// its own MarkdownBody in one scroll view and carries a GlobalKey. Tapping an
/// entry in the collapsible "Contents" card scrolls to that heading; each
/// heading shows a small "↑ Contents" affordance back to the card. The card is
/// hidden below [minHeadings] headings.
///
/// Pinch-to-zoom mirrors ZoomMd: a two-finger pinch rescales all markdown text
/// app-wide via AppState.mdScale (applied by the MaterialApp builder).
class MdWithToc extends StatefulWidget {
  final String data;
  final String title;
  final int minHeadings;
  const MdWithToc({
    super.key,
    required this.data,
    this.title = 'Contents',
    this.minHeadings = 2,
  });

  @override
  State<MdWithToc> createState() => _MdWithTocState();
}

class _MdWithTocState extends State<MdWithToc> {
  final GlobalKey _topKey = GlobalKey();
  late List<MdSection> _sections;
  late List<GlobalKey> _keys;
  late List<Heading> _headings;
  // Shallowest heading level in this document — indentation is relative to
  // it, so an H2-only doc looks exactly as it did before H1 was included.
  int _minLevel = 2;
  // Section index of the document title (a leading H1), or -1 — listed
  // nowhere in the contents, exactly as the web viewer does it.
  int _titleIndex = -1;
  bool _open = false; // Contents card starts collapsed.
  double _startScale = 1.0;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant MdWithToc old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _parse();
  }

  void _parse() {
    _sections = splitSections(widget.data)
        .where((s) => s.heading != null || s.body.trim().isNotEmpty)
        .toList();
    _keys = [for (final _ in _sections) GlobalKey()];
    _titleIndex = leadingTitleIndex(_sections);
    _headings = [
      for (var i = 0; i < _sections.length; i++)
        if (i != _titleIndex && _sections[i].heading != null) _sections[i].heading!
    ];
    _minLevel = _headings.isEmpty
        ? 2
        : _headings.map((h) => h.level).reduce((a, b) => a < b ? a : b);
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300), alignment: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final scale = context.watch<AppState>().mdScale;
    final showToc = _headings.length >= widget.minHeadings;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (_) => _startScale = scale,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return; // one finger = scroll/select as usual
        context
            .read<AppState>()
            .previewMdScale((_startScale * d.scale).clamp(0.6, 3.0).toDouble());
      },
      onScaleEnd: (_) => context.read<AppState>().saveMdScale(),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showToc) _tocCard(context),
            for (var i = 0; i < _sections.length; i++)
              KeyedSubtree(
                key: _keys[i],
                child: _sectionView(context, _sections[i], showToc),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tocCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: _topKey,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 20),
                  const SizedBox(width: 4),
                  Text('${widget.title} (${_headings.length})',
                      style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    if (i != _titleIndex && _sections[i].heading != null)
                      _tocEntry(context, _sections[i].heading!, _keys[i]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tocEntry(BuildContext context, Heading h, GlobalKey key) {
    return InkWell(
      onTap: () => _scrollTo(key),
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(12.0 + (h.level - _minLevel) * 16.0, 6, 12, 6),
        child: Text(h.text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  Widget _sectionView(BuildContext context, MdSection s, bool showBack) {
    final body = MarkdownBody(data: s.body, selectable: true);
    if (s.heading == null) return body;
    final heading = MarkdownBody(data: s.headingLine, selectable: true);
    if (!showBack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, body],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _scrollTo(_topKey),
            icon: const Icon(Icons.arrow_upward, size: 14),
            label: Text(widget.title),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        heading,
        body,
      ],
    );
  }
}
