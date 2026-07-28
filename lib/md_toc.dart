// lib/md_toc.dart
//
// Pure helpers ported from the web dashboard (lib/mdtoc.js). No Flutter
// imports on purpose: unit-testable with `flutter test`, no device needed.
// Keep IDENTICAL across phils-brain-app, book-dashboard-app and
// yt-dashboard-app so anchors and filenames never drift. The widget lives
// in md_toc_view.dart.

// ----------------------------------------------------------------- headings

class Heading {
  final int level;
  final String text;
  final String id;
  const Heading(this.level, this.text, this.id);
}

class MdSection {
  final Heading? heading;
  final String headingLine;
  final String body;
  const MdSection({this.heading, this.headingLine = '', this.body = ''});
}

final RegExp _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _trimDashes = RegExp(r'^-+|-+$');
final RegExp _contentsRe = RegExp(r'^(table of )?contents$', caseSensitive: false);
final RegExp _headingRe = RegExp(r'^(#{1,4})[ \t]+(.+?)[ \t]*$');
final RegExp _fenceRe = RegExp(r'^\s*(```|~~~)');

/// Lowercase kebab slug, deduped: first wins, then -2, -3 ...
String headingSlug(String text, Map<String, int> seen) {
  var base = text.toLowerCase().replaceAll(_nonAlnum, '-').replaceAll(_trimDashes, '');
  if (base.isEmpty) base = 'section';
  final n = (seen[base] ?? 0) + 1;
  seen[base] = n;
  return n > 1 ? '$base-$n' : base;
}

/// Splits a document into a preamble plus one section per H1-H4 heading.
/// H1 counts because the Master Prompt asks for "four top-level headings"
/// and models answer with `# QUESTION 1 …`; ignoring H1 dropped those four
/// from every contents list, and hid the card entirely on runs that put
/// every heading at H1.
/// Headings inside fenced code blocks are ignored, as is a "Contents" heading.
List<MdSection> splitSections(String markdown) {
  final lines = markdown.split('\n');
  final seen = <String, int>{};
  final out = <MdSection>[];
  final buf = StringBuffer();
  var inFence = false;
  Heading? curHeading;
  var curHeadingLine = '';

  void flush() {
    final body = buf.toString();
    if (curHeading != null || body.trim().isNotEmpty) {
      out.add(MdSection(heading: curHeading, headingLine: curHeadingLine, body: body));
    }
    buf.clear();
  }

  for (final line in lines) {
    if (_fenceRe.hasMatch(line)) inFence = !inFence;
    final m = inFence ? null : _headingRe.firstMatch(line);
    if (m != null && !_contentsRe.hasMatch(m.group(2)!.trim())) {
      flush();
      final text = m.group(2)!.trim();
      curHeading = Heading(m.group(1)!.length, text, headingSlug(text, seen));
      curHeadingLine = line;
      continue;
    }
    buf.writeln(line);
  }
  flush();
  return out;
}

final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// Index of the section holding the document's TITLE heading, or -1.
///
/// A title is a LEADING H1 that is BARE: nothing but comments and whitespace
/// between it and the next heading. An H1 that has a body is a real section —
/// a Master Prompt QUESTION whose sub-points are bullets rather than headings —
/// and dropping it would silently lose QUESTION 1 from the contents.
///
/// Web parity: `decorateHeadings` in phils-library/lib/mdtoc.js applies the
/// identical test, so a title is never a contents entry on any surface.
int leadingTitleIndex(List<MdSection> sections) {
  for (var i = 0; i < sections.length; i++) {
    final h = sections[i].heading;
    if (h == null) {
      if (sections[i].body.trim().isNotEmpty) return -1; // real text came first
      continue;
    }
    if (h.level != 1) return -1;
    return sections[i].body.replaceAll(_htmlComment, '').trim().isEmpty ? i : -1;
  }
  return -1;
}

List<Heading> extractHeadings(String markdown) => splitSections(markdown)
    .where((s) => s.heading != null)
    .map((s) => s.heading!)
    .toList();

// ---------------------------------------------------------------- filenames

final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
final RegExp _wsRun = RegExp(r'\s+');
final RegExp _trailing = RegExp(r'[.\s]+$');

/// Readable, NOT a slug: casing and accents survive; only characters the
/// filesystem forbids are removed.
String cleanFileTitle(String s, {int max = 120}) {
  var t = s.replaceAll(_illegal, ' ').replaceAll(_wsRun, ' ').trim().replaceAll(_trailing, '');
  if (t.length > max) {
    t = t.substring(0, max);
    final i = t.lastIndexOf(' ');
    if (i > 0) t = t.substring(0, i);
    t = t.trim();
  }
  return t.isEmpty ? 'Untitled' : t;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 'Who We Are and How We Got Here - Master Analysis - 2026-07-27.md'
String downloadName({
  required String title,
  String kind = '',
  String suffix = '',
  DateTime? date,
  String ext = 'md',
}) {
  final d = date ?? DateTime.now();
  final parts = <String>[
    cleanFileTitle(title),
    if (kind.trim().isNotEmpty) cleanFileTitle(kind, max: 60),
    if (suffix.trim().isNotEmpty) cleanFileTitle(suffix, max: 40),
    '${d.year}-${_two(d.month)}-${_two(d.day)}',
  ];
  return '${parts.join(' - ')}.${ext.replaceFirst(RegExp(r'^\.'), '')}';
}

/// Guarantees the document opens with an H1 equal to its filename stem.
/// An existing, different leading H1 that is the document's TITLE is DEMOTED to
/// H2 rather than discarded. When the document has SEVERAL H1s they are
/// sections (the Master Prompt's four QUESTIONs) — demoting only the first
/// would break the hierarchy, so they are all left alone.
String withTitleHeading(String md, String title) {
  final t = title.trim();
  if (t.isEmpty) return md;
  final s = md.replaceFirst(RegExp(r'^\s+'), '');
  final m = RegExp(r'^#[ \t]+(.+?)[ \t]*(\r?\n|$)').firstMatch(s);
  if (m != null) {
    final existing = m.group(1)!.trim();
    if (existing == t) return s;
    final soleH1 =
        RegExp(r'^#[ \t]+', multiLine: true).allMatches(s).length == 1;
    if (soleH1) {
      final nl = m.group(2)!.isEmpty ? '\n' : m.group(2)!;
      return '# $t\n\n## $existing$nl${s.substring(m.end)}';
    }
  }
  return '# $t\n\n$s';
}