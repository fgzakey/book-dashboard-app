// Data models mirroring the dashboard's API shapes.

class Book {
  final String bookId;
  String? title;
  String? author;
  String? language;
  String? description;
  String? publisher;
  String? filename;
  String? tocSource;
  String? cover; // data URL, only present on the full record
  int wordCount;
  String text; // empty in the light list rows — fetch the full book to fill it
  List<dynamic> segments;
  List<ChatMessage> chat;
  List<dynamic> chapters;
  List<dynamic>? images; // epub images [{id,name,dataUrl,seg,chapterIdx,bytes,title,type,text,description}]
  Map<String, dynamic>? imagesMeta; // {model, cost, at}
  Map<String, dynamic>? scribes; // scopeKey -> {svg, spec, images, mode, artStyle, ...}
  bool hasImages; // list-row flag (full record not loaded yet)
  bool hasScribes;
  int? savedAt; // epoch ms

  Book({
    required this.bookId,
    this.title,
    this.author,
    this.language,
    this.description,
    this.publisher,
    this.filename,
    this.tocSource,
    this.cover,
    this.wordCount = 0,
    this.text = '',
    List<dynamic>? segments,
    List<ChatMessage>? chat,
    List<dynamic>? chapters,
    this.images,
    this.imagesMeta,
    this.scribes,
    this.hasImages = false,
    this.hasScribes = false,
    this.savedAt,
  })  : segments = segments ?? [],
        chat = chat ?? [],
        chapters = chapters ?? [];

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        bookId: j['bookId'] as String,
        title: j['title'] as String?,
        author: j['author'] as String?,
        language: j['language'] as String?,
        description: j['description'] as String?,
        publisher: j['publisher'] as String?,
        filename: j['filename'] as String?,
        tocSource: j['tocSource'] as String?,
        cover: j['cover'] as String?,
        wordCount: (j['wordCount'] as num?)?.toInt() ?? 0,
        text: j['text'] as String? ?? '',
        segments: (j['segments'] as List?) ?? [],
        chat: ((j['chat'] as List?) ?? [])
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        chapters: (j['chapters'] as List?) ?? [],
        images: j['images'] as List?,
        imagesMeta: j['imagesMeta'] == null
            ? null
            : Map<String, dynamic>.from(j['imagesMeta']),
        scribes: j['scribes'] == null
            ? null
            : Map<String, dynamic>.from(j['scribes']),
        hasImages: j['hasImages'] as bool? ?? false,
        hasScribes: j['hasScribes'] as bool? ?? false,
        savedAt: (j['savedAt'] as num?)?.toInt(),
      );

  /// Full payload for upsert. The server COALESCEs null images/scribes/cover,
  /// so omitting them (when not loaded) preserves what's already in the DB.
  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'title': title,
        'author': author,
        'language': language,
        'description': description,
        'publisher': publisher,
        'filename': filename,
        'tocSource': tocSource,
        if (cover != null) 'cover': cover,
        'wordCount': wordCount,
        'text': text,
        'segments': segments,
        'chat': chat.map((m) => m.toJson()).toList(),
        'chapters': chapters,
        if (images != null) 'images': images,
        if (imagesMeta != null) 'imagesMeta': imagesMeta,
        if (scribes != null) 'scribes': scribes,
      };

  bool get fullLoaded => text.isNotEmpty || segments.isNotEmpty;

  /// Text of chapter [i], reconstructed from segments (same as the web's
  /// chapterTextOf). Chapters own segments [startSeg, next.startSeg).
  String chapterText(int i, {int? maxChars}) {
    if (i < 0 || i >= chapters.length) return '';
    final start = ((chapters[i] as Map)['startSeg'] as num?)?.toInt() ?? 0;
    final end = i + 1 < chapters.length
        ? ((chapters[i + 1] as Map)['startSeg'] as num?)?.toInt() ?? segments.length
        : segments.length;
    final buf = StringBuffer();
    for (var s = start; s < end && s < segments.length; s++) {
      final t = ((segments[s] as Map)['text'] ?? '').toString();
      if (t.isEmpty) continue;
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write(t);
      if (maxChars != null && buf.length > maxChars) break;
    }
    var out = buf.toString();
    if (maxChars != null && out.length > maxChars) out = out.substring(0, maxChars);
    return out;
  }

  /// Which chapter an image belongs to (segment anchor survives
  /// re-chapterizing) — port of the web's imageChapterIdx.
  int? imageChapterIdx(Map<String, dynamic> img) {
    final seg = (img['seg'] as num?)?.toInt();
    if (seg != null && chapters.isNotEmpty) {
      var idx = 0;
      for (var i = 0; i < chapters.length; i++) {
        final start = ((chapters[i] as Map)['startSeg'] as num?)?.toInt() ?? 0;
        if (start <= seg) idx = i;
      }
      return idx;
    }
    final ci = (img['chapterIdx'] as num?)?.toInt();
    if (ci != null && ci < chapters.length) return ci;
    return null;
  }
}

class ChatMessage {
  final String role; // user | assistant
  final String content;
  final String? model;
  final String? cost;

  ChatMessage({required this.role, required this.content, this.model, this.cost});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String? ?? 'user',
        content: j['content'] as String? ?? '',
        model: j['model'] as String?,
        cost: j['cost']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (model != null) 'model': model,
        if (cost != null) 'cost': cost,
      };
}

class PromptTemplate {
  final String id;
  String name;
  String description;
  String template;
  final bool builtin;

  PromptTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.template = '',
    this.builtin = false,
  });

  factory PromptTemplate.fromJson(Map<String, dynamic> j) => PromptTemplate(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        template: j['template'] as String? ?? '',
        builtin: j['builtin'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'template': template,
      };

  /// Same substitution as lib/prompts.js fillTemplate on the web.
  String fill({required String title, required String author, required String booktext}) =>
      template
          .replaceAll('{{booktext}}', booktext)
          .replaceAll('{{transcript}}', booktext)
          .replaceAll('{{title}}', title)
          .replaceAll('{{author}}', author.isEmpty ? 'Unknown author' : author);
}

class SavedResult {
  final dynamic id;
  final String? bookId;
  final String? bookTitle;
  final String? promptName;
  final String? scope;
  final String content;
  final String? model;
  final String? cost;
  final String? createdAt;

  SavedResult({
    this.id,
    this.bookId,
    this.bookTitle,
    this.promptName,
    this.scope,
    required this.content,
    this.model,
    this.cost,
    this.createdAt,
  });

  factory SavedResult.fromJson(Map<String, dynamic> j) => SavedResult(
        id: j['id'],
        bookId: j['book_id'] as String?,
        bookTitle: j['book_title'] as String?,
        promptName: j['prompt_name'] as String?,
        scope: j['scope'] as String?,
        content: j['content'] as String? ?? '',
        model: j['model'] as String?,
        cost: j['cost']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

class ModelInfo {
  final String id;
  final String name;
  final int? context;
  final String? promptPrice;
  final String? completionPrice;
  final List<String> inputModalities; // e.g. ["text","image"]

  ModelInfo({
    required this.id,
    required this.name,
    this.context,
    this.promptPrice,
    this.completionPrice,
    this.inputModalities = const [],
  });

  bool get vision => inputModalities.contains('image');

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        context: (j['context'] as num?)?.toInt(),
        promptPrice: j['promptPrice']?.toString(),
        completionPrice: j['completionPrice']?.toString(),
        inputModalities: ((j['inputModalities'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ChatResponse {
  final String content;
  final String? model;
  final Map<String, dynamic>? usage;

  ChatResponse({required this.content, this.model, this.usage});

  /// USD cost string, from OpenRouter's usage.cost when present.
  String? get cost => formatUsageCost(usage);
}

/// "$0.0042"-style cost from an OpenRouter usage object, or null.
String? formatUsageCost(Map<String, dynamic>? usage) {
  final c = usage?['cost'];
  if (c == null) return null;
  final v = c is num ? c.toDouble() : double.tryParse(c.toString());
  if (v == null || v == 0) return null;
  return v < 0.01 ? '\$${v.toStringAsFixed(6)}' : '\$${v.toStringAsFixed(4)}';
}

// ---- Visual Scribe options (ids must match lib/prompts.js on the server) ----

class ScribeOption {
  final String id;
  final String name;
  const ScribeOption(this.id, this.name);
}

const scribeModes = [
  ScribeOption('whiteboard', 'Whiteboard (graphic recording)'),
  ScribeOption('palace', 'Memory palace (method of loci)'),
  ScribeOption('graph', 'Knowledge graph (semantic map)'),
];

const scribeArtStyles = [
  ScribeOption('marker', 'Whiteboard marker (classic)'),
  ScribeOption('editorial', 'Editorial ink'),
  ScribeOption('isometric', 'Isometric diorama'),
  ScribeOption('codex', 'Da Vinci codex'),
  ScribeOption('watercolor', 'Watercolor sketchnote'),
  ScribeOption('retro', 'Retro-futurist poster'),
  ScribeOption('chalk', 'Chalkboard chiaroscuro'),
];
