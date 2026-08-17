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
  int? savedAt; // epoch ms — `updated_at`, i.e. LAST MODIFIED
  int? addedAt; // `created_at`
  int? openedAt; // `last_opened_at`, written only by touchBook
  int? extractedAt; // MAX(book_results.created_at) for this book

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
    this.addedAt,
    this.openedAt,
    this.extractedAt,
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
        addedAt: (j['addedAt'] as num?)?.toInt(),
        openedAt: (j['openedAt'] as num?)?.toInt(),
        extractedAt: (j['extractedAt'] as num?)?.toInt(),
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

/// Book-list orderings, mirroring the web dashboard's `LIBRARY_SORTS` in
/// `phils-library/app/library-search.js`.
enum BookSort { savedAt, opened, added, extracted }

extension BookSortLabel on BookSort {
  String get label => switch (this) {
        BookSort.savedAt => 'Last modified',
        BookSort.opened => 'Last accessed',
        BookSort.added => 'Date added',
        BookSort.extracted => 'Last extracted',
      };

  int? keyOf(Book b) => switch (this) {
        BookSort.savedAt => b.savedAt,
        BookSort.opened => b.openedAt,
        BookSort.added => b.addedAt,
        BookSort.extracted => b.extractedAt,
      };
}

/// Short label for the value the list is CURRENTLY ordered by.
String sortStamp(Book b, BookSort sort) {
  if (sort == BookSort.savedAt) return '';
  const verbs = {
    BookSort.opened: 'opened',
    BookSort.added: 'added',
    BookSort.extracted: 'extracted',
  };
  final verb = verbs[sort];
  if (verb == null) return '';
  final ms = sort.keyOf(b);
  if (ms == null) return 'never $verb';

  final then = DateTime.fromMillisecondsSinceEpoch(ms);
  final days = DateTime.now().difference(then).inDays;
  if (days <= 0) return '$verb today';
  if (days == 1) return '$verb yesterday';
  if (days < 30) return '$verb ${days}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '$verb ${then.day} ${months[then.month - 1]} ${then.year}';
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

/// A syntopical synthesis essay from the knowledge graph (served by
/// /api/essays). The [body] is Markdown; [targetTitle] is the idea/theme the
/// essay synthesizes across the library.
class Essay {
  final dynamic id;
  final String slug;
  final String title;
  final String body;
  final String? targetTitle;
  final String? targetType;
  final String? updatedAt;

  Essay({
    this.id,
    required this.slug,
    required this.title,
    required this.body,
    this.targetTitle,
    this.targetType,
    this.updatedAt,
  });

  factory Essay.fromJson(Map<String, dynamic> j) => Essay(
        id: j['id'],
        slug: j['slug']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Untitled essay',
        body: j['body']?.toString() ?? '',
        targetTitle: j['target_title']?.toString(),
        targetType: j['target_type']?.toString(),
        updatedAt: j['updated_at']?.toString(),
      );
}

// ---- Workspaces / Multi-user databases ----

class WorkspaceInfo {
  final String? owner; // null for canon
  final String name;
  final String kind; // canon | fork | clean | external
  final String label;
  final bool isCanon;
  final bool active;
  final bool mine;
  final bool canWrite;
  final bool canDelete;
  final int books;
  final int videos;
  final int results;
  final int boards;
  final int scenes;

  WorkspaceInfo({
    this.owner,
    required this.name,
    this.kind = 'fork',
    required this.label,
    this.isCanon = false,
    this.active = false,
    this.mine = true,
    this.canWrite = true,
    this.canDelete = false,
    this.books = 0,
    this.videos = 0,
    this.results = 0,
    this.boards = 0,
    this.scenes = 0,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> j) => WorkspaceInfo(
        owner: j['owner'] as String?,
        name: j['name']?.toString() ?? 'canon',
        kind: j['kind']?.toString() ?? 'canon',
        label: j['label']?.toString() ?? (j['name']?.toString() ?? 'canon'),
        isCanon: j['isCanon'] as bool? ?? (j['kind'] == 'canon'),
        active: j['active'] as bool? ?? false,
        mine: j['mine'] as bool? ?? true,
        canWrite: j['canWrite'] as bool? ?? true,
        canDelete: j['canDelete'] as bool? ?? false,
        books: (j['books'] as num?)?.toInt() ?? 0,
        videos: (j['videos'] as num?)?.toInt() ?? 0,
        results: (j['results'] as num?)?.toInt() ?? 0,
        boards: (j['boards'] as num?)?.toInt() ?? 0,
        scenes: (j['scenes'] as num?)?.toInt() ?? 0,
      );
}

class WorkspacesResponse {
  final String member;
  final bool admin;
  final WorkspaceInfo? active;
  final List<WorkspaceInfo> workspaces;

  WorkspacesResponse({
    this.member = 'admin',
    this.admin = true,
    this.active,
    this.workspaces = const [],
  });

  factory WorkspacesResponse.fromJson(Map<String, dynamic> j) => WorkspacesResponse(
        member: j['member']?.toString() ?? 'admin',
        admin: j['admin'] as bool? ?? false,
        active: j['active'] is Map
            ? WorkspaceInfo.fromJson(Map<String, dynamic>.from(j['active']))
            : null,
        workspaces: ((j['workspaces'] as List?) ?? [])
            .map((w) => WorkspaceInfo.fromJson(Map<String, dynamic>.from(w)))
            .toList(),
      );
}

// ---- Mnemonic scenes ----

class MnemonicSource {
  final String sourceKind; // book | video
  final String sourceId;
  final String sourceTitle;
  final int imageCount;
  final int boardCount;
  final String? latest;

  MnemonicSource({
    required this.sourceKind,
    required this.sourceId,
    required this.sourceTitle,
    this.imageCount = 0,
    this.boardCount = 0,
    this.latest,
  });

  factory MnemonicSource.fromJson(Map<String, dynamic> j) => MnemonicSource(
        sourceKind: j['source_kind']?.toString() ?? 'book',
        sourceId: j['source_id']?.toString() ?? '',
        sourceTitle: j['source_title']?.toString() ?? '(untitled source)',
        imageCount: (j['image_count'] as num?)?.toInt() ?? 0,
        boardCount: (j['board_count'] as num?)?.toInt() ?? 0,
        latest: j['latest']?.toString(),
      );
}

class MnemonicHotspot {
  final int i;
  final String heading;
  final String theme;
  final String colorHex;
  final List<String> points;
  final double? x;
  final double? y;
  final String placed; // vision | legend

  MnemonicHotspot({
    required this.i,
    required this.heading,
    this.theme = '',
    this.colorHex = '',
    this.points = const [],
    this.x,
    this.y,
    this.placed = 'legend',
  });

  factory MnemonicHotspot.fromJson(Map<String, dynamic> j) => MnemonicHotspot(
        i: (j['i'] as num?)?.toInt() ?? 0,
        heading: j['heading']?.toString() ?? '',
        theme: j['theme']?.toString() ?? '',
        colorHex: j['color']?.toString() ?? '',
        points: ((j['points'] as List?) ?? []).map((p) => p.toString()).toList(),
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        placed: j['placed']?.toString() ?? 'legend',
      );
}

class MnemonicScene {
  final dynamic id;
  final String sourceKind;
  final String sourceId;
  final String sourceTitle;
  final String boardKey;
  final String variant;
  final String? style;
  final String? styleName;
  final String? model;
  final int? width;
  final int? height;
  final String? sourceResolution;
  final List<MnemonicHotspot> hotspots;
  final String? createdAt;
  final int imageChars;
  final String? image; // data URL, only on single-row fetch

  MnemonicScene({
    this.id,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceTitle,
    required this.boardKey,
    this.variant = 'clean',
    this.style,
    this.styleName,
    this.model,
    this.width,
    this.height,
    this.sourceResolution,
    this.hotspots = const [],
    this.createdAt,
    this.imageChars = 0,
    this.image,
  });

  factory MnemonicScene.fromJson(Map<String, dynamic> j) {
    final image = j['image']?.toString();
    return MnemonicScene(
      id: j['id'],
      sourceKind: j['source_kind']?.toString() ?? 'book',
      sourceId: j['source_id']?.toString() ?? '',
      sourceTitle: j['source_title']?.toString() ?? '(untitled source)',
      boardKey: j['board_key']?.toString() ?? '',
      variant: j['variant']?.toString() ?? 'clean',
      style: j['style']?.toString(),
      styleName: j['style_name']?.toString(),
      model: j['model']?.toString(),
      width: (j['width'] as num?)?.toInt(),
      height: (j['height'] as num?)?.toInt(),
      sourceResolution: j['source_resolution']?.toString(),
      hotspots: ((j['hotspots'] as List?) ?? [])
          .map((h) => MnemonicHotspot.fromJson(Map<String, dynamic>.from(h)))
          .toList(),
      createdAt: j['created_at']?.toString(),
      imageChars: (j['image_chars'] as num?)?.toInt() ?? image?.length ?? 0,
      image: image,
    );
  }
}
