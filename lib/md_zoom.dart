import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';

/// Markdown with pinch-to-zoom text scaling.
///
/// A two-finger pinch anywhere on the content rescales ALL rendered markdown
/// text app-wide: the factor lives in AppState.mdScale, updates live during
/// the gesture, and is persisted when the pinch ends. One-finger gestures
/// (scroll, text selection) behave exactly as before.
///
/// Use [scrollable] for a full-page scrolling Markdown view; leave it false
/// to embed inline (MarkdownBody), e.g. inside chat bubbles.
class ZoomMd extends StatefulWidget {
  final String data;
  final bool scrollable;
  const ZoomMd({super.key, required this.data, this.scrollable = false});

  @override
  State<ZoomMd> createState() => _ZoomMdState();
}

class _ZoomMdState extends State<ZoomMd> {
  double _startScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final scale = context.watch<AppState>().mdScale;
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
      // The scale itself is applied app-wide by the MaterialApp builder
      // (MediaQuery textScaler), so no extra MediaQuery here — it would
      // compound the factor twice.
      child: widget.scrollable
          ? Markdown(data: widget.data, selectable: true)
          : MarkdownBody(data: widget.data, selectable: true),
    );
  }
}
