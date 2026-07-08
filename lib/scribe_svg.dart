// Dart port of the web dashboard's lib/scribe.js — composes the graphic-
// recording "whiteboard" SVG from a scribe spec plus AI illustrations
// (embedded as <image href="data:...">). Keeping the output identical means
// boards generated on the phone render the same in the web app and vice versa
// (they share the same DB record shape: {svg, spec, images, ...}).

const _defaults = {
  'paper': '#fbf7ef',
  'ink': '#1f2937',
  'accent': '#e8590c',
  'accent2': '#1c7ed6',
};

const _themeColors = {
  'Love & Connection': '#e64980',
  'Creativity & Play': '#f59f00',
  'Liberty & Abundance': '#12b886',
  'Character & Personality': '#7048e8',
  'Wisdom & Intelligence': '#1c7ed6',
  'Progress & Exploration': '#e8590c',
};

String _esc(dynamic s) => (s == null ? '' : s.toString())
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Naive word-wrap into lines of at most [max] characters.
List<String> _wrap(dynamic text, int max) {
  final words = (text == null ? '' : text.toString())
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final lines = <String>[];
  var line = '';
  for (final w in words) {
    if (line.isEmpty) {
      line = w;
    } else if ('$line $w'.length <= max) {
      line = '$line $w';
    } else {
      lines.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

/// Small hand-drawn doodle icons keyed by keyword, centered in a box of [s]
/// at (x,y). Falls back to a simple sketch mark.
String _icon(String? name, double x, double y, double s, String color) {
  final st =
      'fill="none" stroke="$color" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"';
  String c(double cx, double cy, double r) =>
      '<circle cx="$cx" cy="$cy" r="$r" $st/>';
  String g(String inner) =>
      '<g transform="translate($x,$y)" filter="url(#rough)">$inner</g>';
  final h = s, w = s;
  switch ((name ?? '').toLowerCase()) {
    case 'lightbulb':
      return g('<circle cx="${w / 2}" cy="${h * 0.4}" r="${h * 0.28}" $st/><path d="M${w * 0.4} ${h * 0.68} L${w * 0.6} ${h * 0.68} M${w * 0.42} ${h * 0.8} L${w * 0.58} ${h * 0.8}" $st/>');
    case 'brain':
      return g('<path d="M${w * 0.5} ${h * 0.2} C${w * 0.2} ${h * 0.15}, ${w * 0.15} ${h * 0.6}, ${w * 0.4} ${h * 0.8} M${w * 0.5} ${h * 0.2} C${w * 0.8} ${h * 0.15}, ${w * 0.85} ${h * 0.6}, ${w * 0.6} ${h * 0.8} M${w * 0.5} ${h * 0.2} L${w * 0.5} ${h * 0.8}" $st/>');
    case 'heart':
      return g('<path d="M${w * 0.5} ${h * 0.78} C${w * 0.1} ${h * 0.5}, ${w * 0.25} ${h * 0.15}, ${w * 0.5} ${h * 0.38} C${w * 0.75} ${h * 0.15}, ${w * 0.9} ${h * 0.5}, ${w * 0.5} ${h * 0.78} Z" $st/>');
    case 'star':
      return g('<path d="M${w * 0.5} ${h * 0.15} L${w * 0.61} ${h * 0.42} L${w * 0.9} ${h * 0.44} L${w * 0.67} ${h * 0.63} L${w * 0.75} ${h * 0.9} L${w * 0.5} ${h * 0.73} L${w * 0.25} ${h * 0.9} L${w * 0.33} ${h * 0.63} L${w * 0.1} ${h * 0.44} L${w * 0.39} ${h * 0.42} Z" $st/>');
    case 'gear':
      return g('${c(w / 2, h / 2, h * 0.22)}<path d="M${w * 0.5} ${h * 0.12} L${w * 0.5} ${h * 0.24} M${w * 0.5} ${h * 0.76} L${w * 0.5} ${h * 0.88} M${w * 0.12} ${h * 0.5} L${w * 0.24} ${h * 0.5} M${w * 0.76} ${h * 0.5} L${w * 0.88} ${h * 0.5} M${w * 0.24} ${h * 0.24} L${w * 0.32} ${h * 0.32} M${w * 0.68} ${h * 0.68} L${w * 0.76} ${h * 0.76} M${w * 0.76} ${h * 0.24} L${w * 0.68} ${h * 0.32} M${w * 0.32} ${h * 0.68} L${w * 0.24} ${h * 0.76}" $st/>');
    case 'compass':
      return g('${c(w / 2, h / 2, h * 0.35)}<path d="M${w * 0.5} ${h * 0.5} L${w * 0.62} ${h * 0.36} L${w * 0.5} ${h * 0.5} L${w * 0.4} ${h * 0.66}" $st/>');
    case 'book':
      return g('<path d="M${w * 0.15} ${h * 0.25} Q${w * 0.5} ${h * 0.15}, ${w * 0.5} ${h * 0.25} L${w * 0.5} ${h * 0.8} Q${w * 0.5} ${h * 0.7}, ${w * 0.15} ${h * 0.8} Z M${w * 0.85} ${h * 0.25} Q${w * 0.5} ${h * 0.15}, ${w * 0.5} ${h * 0.25} L${w * 0.5} ${h * 0.8} Q${w * 0.5} ${h * 0.7}, ${w * 0.85} ${h * 0.8} Z" $st/>');
    case 'arrow':
      return g('<path d="M${w * 0.15} ${h * 0.5} L${w * 0.78} ${h * 0.5} M${w * 0.58} ${h * 0.32} L${w * 0.82} ${h * 0.5} L${w * 0.58} ${h * 0.68}" $st/>');
    case 'target':
      return g('${c(w / 2, h / 2, h * 0.34)}${c(w / 2, h / 2, h * 0.2)}${c(w / 2, h / 2, h * 0.06)}');
    case 'seed':
      return g('<path d="M${w * 0.5} ${h * 0.85} L${w * 0.5} ${h * 0.45} M${w * 0.5} ${h * 0.5} C${w * 0.3} ${h * 0.4}, ${w * 0.3} ${h * 0.2}, ${w * 0.5} ${h * 0.25} C${w * 0.7} ${h * 0.2}, ${w * 0.7} ${h * 0.4}, ${w * 0.5} ${h * 0.5}" $st/>');
    case 'mountain':
      return g('<path d="M${w * 0.12} ${h * 0.78} L${w * 0.4} ${h * 0.28} L${w * 0.58} ${h * 0.55} L${w * 0.72} ${h * 0.35} L${w * 0.9} ${h * 0.78} Z" $st/>');
    case 'key':
      return g('${c(w * 0.32, h * 0.4, h * 0.16)}<path d="M${w * 0.44} ${h * 0.5} L${w * 0.82} ${h * 0.78} M${w * 0.7} ${h * 0.66} L${w * 0.78} ${h * 0.58} M${w * 0.62} ${h * 0.58} L${w * 0.7} ${h * 0.5}" $st/>');
    case 'clock':
      return g('${c(w / 2, h / 2, h * 0.34)}<path d="M${w * 0.5} ${h * 0.3} L${w * 0.5} ${h * 0.5} L${w * 0.66} ${h * 0.6}" $st/>');
    case 'eye':
      return g('<path d="M${w * 0.12} ${h * 0.5} Q${w * 0.5} ${h * 0.18}, ${w * 0.88} ${h * 0.5} Q${w * 0.5} ${h * 0.82}, ${w * 0.12} ${h * 0.5} Z" $st/>${c(w / 2, h / 2, h * 0.12)}');
    case 'network':
      return g('${c(w * 0.5, h * 0.22, h * 0.1)}${c(w * 0.22, h * 0.75, h * 0.1)}${c(w * 0.78, h * 0.75, h * 0.1)}<path d="M${w * 0.5} ${h * 0.3} L${w * 0.26} ${h * 0.66} M${w * 0.5} ${h * 0.3} L${w * 0.74} ${h * 0.66} M${w * 0.3} ${h * 0.75} L${w * 0.7} ${h * 0.75}" $st/>');
    default:
      return g('${c(w / 2, h / 2, h * 0.3)}<path d="M${w * 0.5} ${h * 0.32} L${w * 0.5} ${h * 0.55} M${w * 0.5} ${h * 0.66} L${w * 0.5} ${h * 0.68}" $st/>');
  }
}

/// Rough rectangle path (hand-drawn feel comes from the #rough filter).
String _roughRect(double x, double y, double w, double h, double r) =>
    'M${x + r} $y H${x + w - r} Q${x + w} $y ${x + w} ${y + r} V${y + h - r} Q${x + w} ${y + h} ${x + w - r} ${y + h} H${x + r} Q$x ${y + h} $x ${y + h - r} V${y + r} Q$x $y ${x + r} $y Z';

String buildScribeSvg(Map<String, dynamic>? specIn, List<dynamic>? imagesIn) {
  final spec = specIn ?? {};
  final images = (imagesIn ?? [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
  final p = {..._defaults, ...Map<String, dynamic>.from(spec['palette'] ?? {})}
      .map((k, v) => MapEntry(k, v.toString()));
  const W = 1600.0, H = 1000.0;
  final sections = ((spec['sections'] as List?) ?? [])
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .take(7)
      .toList();
  Map<String, dynamic>? hero;
  for (final im in images) {
    if (im['role'] == 'hero') {
      hero = im;
      break;
    }
  }
  hero ??= images.isNotEmpty ? images.first : null;
  final spots = images.where((i) => !identical(i, hero)).toList();

  final out = <String>[];
  out.add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W.toInt()} ${H.toInt()}" font-family="\'Kalam\', \'Comic Sans MS\', cursive">');
  out.add('''<defs>
    <style>@import url('https://fonts.googleapis.com/css2?family=Caveat:wght@600;700&amp;family=Kalam:wght@400;700&amp;display=swap');</style>
    <filter id="rough"><feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="2" seed="7" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="3.2"/></filter>
    <filter id="softshadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="3" dy="4" stdDeviation="3" flood-color="#00000022"/></filter>
    <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="${p['accent2']}"/></marker>
  </defs>''');

  // Background + subtle dot grid
  out.add('<rect width="${W.toInt()}" height="${H.toInt()}" fill="${p['paper']}"/>');
  out.add('<g opacity="0.06">');
  for (var gx = 40; gx < W; gx += 40) {
    for (var gy = 40; gy < H; gy += 40) {
      out.add('<circle cx="$gx" cy="$gy" r="1.4" fill="${p['ink']}"/>');
    }
  }
  out.add('</g>');

  // Title block
  final title = _esc(spec['title'] ?? 'Untitled');
  final subtitle = _esc(spec['subtitle'] ?? '');
  out.add('<text x="60" y="96" font-family="\'Caveat\', cursive" font-size="76" font-weight="700" fill="${p['ink']}">$title</text>');
  out.add('<path d="M62 116 q170 -14 360 2" filter="url(#rough)" fill="none" stroke="${p['accent']}" stroke-width="6" stroke-linecap="round"/>');
  if (subtitle.isNotEmpty) {
    out.add('<text x="64" y="152" font-size="30" fill="${p['ink']}" opacity="0.8">$subtitle</text>');
  }

  // ---- Unified tile layout: hero (top-right), section cards, spot images ----
  final validSpots =
      spots.where((s) => (s['url'] ?? '').toString().isNotEmpty).toList();
  final nHero = hero != null && (hero['url'] ?? '').toString().isNotEmpty ? 1 : 0;
  const gutter = 24.0;
  const gridLeft = 56.0;
  const gridRight = W - 56.0;
  const top = 178.0;
  final bannerQuote = (spec['bannerQuote'] ?? '').toString();
  final bottom = bannerQuote.isNotEmpty ? 852.0 : 946.0;
  final cols = sections.length <= 4 ? 2 : 3;
  final totalTiles = sections.length + nHero + validSpots.length;
  final rows = (totalTiles / cols).ceil().clamp(1, 1000).toInt();
  final cellW = (gridRight - gridLeft - gutter * (cols - 1)) / cols;
  final cellH =
      ((bottom - top - gutter * (rows - 1)) / rows).clamp(0.0, 232.0).toDouble();
  Map<String, double> cellRect(int i) {
    final col = i % cols, row = i ~/ cols;
    return {
      'x': gridLeft + col * (cellW + gutter),
      'y': top + row * (cellH + gutter),
      'w': cellW,
      'h': cellH,
    };
  }

  // Reserve the top-right cell for the hero; sections then spots fill the rest.
  final heroCell = nHero == 1 ? cols - 1 : -1;
  final freeCells = <int>[];
  for (var i = 0; i < rows * cols; i++) {
    if (i != heroCell) freeCells.add(i);
  }
  final sectionCells = freeCells.take(sections.length).toList();
  final spotCells = freeCells
      .skip(sections.length)
      .take(validSpots.length)
      .toList();
  final centers = <Map<String, double>>[];

  void framedImage(String url, Map<String, double> r, String id) {
    out.add('<g filter="url(#softshadow)"><path d="${_roughRect(r['x']!, r['y']!, r['w']!, r['h']!, 16)}" filter="url(#rough)" fill="#ffffff" stroke="${p['ink']}" stroke-width="3"/></g>');
    out.add('<clipPath id="$id"><rect x="${r['x']! + 5}" y="${r['y']! + 5}" width="${r['w']! - 10}" height="${r['h']! - 10}" rx="12"/></clipPath>');
    out.add('<image href="${_esc(url)}" x="${r['x']! + 5}" y="${r['y']! + 5}" width="${r['w']! - 10}" height="${r['h']! - 10}" preserveAspectRatio="xMidYMid slice" clip-path="url(#$id)"/>');
  }

  // Hero illustration
  if (nHero == 1) framedImage(hero!['url'].toString(), cellRect(heroCell), 'heroClip');

  // Section cards
  for (var idx = 0; idx < sections.length; idx++) {
    final sec = sections[idx];
    final r = cellRect(sectionCells[idx]);
    final x = r['x']!, y = r['y']!, cardW = r['w']!, cardH = r['h']!;
    centers.add({'x': x + cardW / 2, 'y': y + cardH / 2});
    final themeColor =
        _themeColors[(sec['theme'] ?? '').toString()] ?? p['accent2']!;
    out.add('<g filter="url(#softshadow)"><path d="${_roughRect(x, y, cardW, cardH, 14)}" filter="url(#rough)" fill="#ffffff" stroke="${p['ink']}" stroke-width="2.6"/></g>');
    out.add('<path d="${_roughRect(x, y, 12, cardH, 6)}" filter="url(#rough)" fill="$themeColor"/>');
    out.add('<circle cx="${x + 34}" cy="${y + 34}" r="18" fill="$themeColor" filter="url(#rough)"/><text x="${x + 34}" y="${y + 41}" text-anchor="middle" font-family="\'Caveat\', cursive" font-weight="700" font-size="26" fill="#fff">${idx + 1}</text>');
    final headLines = _wrap(sec['heading'] ?? '', 22).take(2).toList();
    for (var i = 0; i < headLines.length; i++) {
      out.add('<text x="${x + 62}" y="${y + 34 + i * 30}" font-family="\'Caveat\', cursive" font-weight="700" font-size="30" fill="${p['ink']}">${_esc(headLines[i])}</text>');
    }
    out.add(_icon((sec['icon'] ?? '').toString(), x + cardW - 52, y + 14, 40,
        themeColor));
    final points = ((sec['points'] as List?) ?? []).take(4).toList();
    var py = y + 46 + headLines.length * 26 + 8;
    final maxChars = (cardW / 9.5).floor();
    for (final pt in points) {
      final lines = _wrap(pt, maxChars).take(2).toList();
      out.add('<circle cx="${x + 30}" cy="${py - 6}" r="3.4" fill="${p['accent']}"/>');
      for (var i = 0; i < lines.length; i++) {
        out.add('<text x="${x + 44}" y="${py + i * 22}" font-size="21" fill="${p['ink']}">${_esc(lines[i])}</text>');
      }
      py += 22 * lines.length + 8;
      if (py > y + cardH - 10) break;
    }
  }

  // Connectors (curved dashed arrows between section cards)
  final connectors = ((spec['connectors'] as List?) ?? []).whereType<Map>();
  for (final con in connectors) {
    final from = (con['from'] as num?)?.toInt() ?? -1;
    final to = (con['to'] as num?)?.toInt() ?? -1;
    if (from < 0 || from >= centers.length || to < 0 || to >= centers.length) {
      continue;
    }
    final a = centers[from], b = centers[to];
    if (from == to) continue;
    final mx = (a['x']! + b['x']!) / 2, my = (a['y']! + b['y']!) / 2 - 40;
    out.add('<path d="M${a['x']} ${a['y']} Q$mx $my ${b['x']} ${b['y']}" fill="none" stroke="${p['accent2']}" stroke-width="2.4" stroke-dasharray="2 8" stroke-linecap="round" marker-end="url(#arrow)" opacity="0.5" filter="url(#rough)"/>');
    final label = (con['label'] ?? '').toString();
    if (label.isNotEmpty) {
      out.add('<text x="$mx" y="${my + 4}" text-anchor="middle" font-family="\'Caveat\', cursive" font-size="22" fill="${p['accent2']}">${_esc(label)}</text>');
    }
  }

  // Spot illustrations, each in its own tile
  for (var i = 0; i < validSpots.length && i < spotCells.length; i++) {
    framedImage(validSpots[i]['url'].toString(), cellRect(spotCells[i]), 'spot$i');
  }

  // Banner quote ribbon
  if (bannerQuote.isNotEmpty) {
    const by = 872.0, bh = 92.0, bx = 56.0, bw = W - 112.0;
    out.add('<path d="${_roughRect(bx, by, bw, bh, 14)}" filter="url(#rough)" fill="${p['accent']}" opacity="0.14" stroke="${p['accent']}" stroke-width="2.4"/>');
    final q = _wrap(bannerQuote, (bw / 15).floor()).take(2).toList();
    out.add('<text x="${bx + 26}" y="${by + 40}" font-family="\'Caveat\', cursive" font-size="40" fill="${p['accent']}">&#8220;</text>');
    for (var i = 0; i < q.length; i++) {
      out.add('<text x="${bx + 60}" y="${by + 40 + i * 30}" font-family="\'Caveat\', cursive" font-weight="700" font-size="30" fill="${p['ink']}">${_esc(q[i])}</text>');
    }
  }

  out.add('<text x="${(W - 20).toInt()}" y="${(H - 14).toInt()}" text-anchor="end" font-size="16" fill="${p['ink']}" opacity="0.4">visual scribe · ${_esc(spec['title'] ?? '')}</text>');
  out.add('</svg>');
  return out.join('\n');
}
