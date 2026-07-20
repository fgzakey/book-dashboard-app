import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Tolerantly parse a JSON object from a model reply (strips code fences /
/// surrounding prose). Returns null if nothing parses.
Map<String, dynamic>? _looseJson(String? content) {
  if (content == null) return null;
  var text = content.trim().replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'```\s*$'), '').trim();
  try {
    final v = jsonDecode(text);
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  final m = RegExp(r'\{[\s\S]*\}').firstMatch(text);
  if (m != null) {
    try {
      final v = jsonDecode(m.group(0)!);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
  }
  return null;
}

/// Prefilled server address — the deployed Space. Only the app password is
/// needed on first run; override the URL in Settings to point elsewhere.
const String kDefaultServerUrl = 'https://fgza-book-dashboard.hf.space';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  bool loadedPrefs = false;
  String model = 'google/gemini-2.5-flash';
  double temperature = 0.4;

  /// Global text scale — applies to ALL text incl. Markdown (via the
  /// MaterialApp MediaQuery builder). Change it by pinching on markdown
  /// content or with the A−/A+ buttons; persisted across launches.
  double mdScale = 1.0;

  // Feature-specific model choices (same defaults as the web dashboard).
  String imagesModel = ''; // vision model for AI describe
  String scribeImageModel = 'google/gemini-2.5-flash-image';
  String scribeMode = 'whiteboard';
  String scribeArtStyle = 'marker';
  bool scribeGenImages = true;

  List<Book> books = [];
  List<PromptTemplate> prompts = []; // builtins + custom, builtins first
  List<ModelInfo> models = [];
  List<Essay> essays = [];

  bool loadingBooks = false;
  String? booksError;
  bool loadingEssays = false;
  String? essaysError;

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final savedUrl = p.getString('baseUrl');
    api.baseUrl = (savedUrl == null || savedUrl.isEmpty) ? kDefaultServerUrl : savedUrl;
    api.password = p.getString('password') ?? '';
    api.apiKey = p.getString('apiKey') ?? '';
    model = p.getString('model') ?? model;
    temperature = p.getDouble('temperature') ?? 0.4;
    mdScale = p.getDouble('mdScale') ?? 1.0;
    imagesModel = p.getString('imagesModel') ?? '';
    scribeImageModel = p.getString('scribeImageModel') ?? scribeImageModel;
    scribeMode = p.getString('scribeMode') ?? scribeMode;
    scribeArtStyle = p.getString('scribeArtStyle') ?? scribeArtStyle;
    scribeGenImages = p.getBool('scribeGenImages') ?? true;
    loadedPrefs = true;
    notifyListeners();
  }

  /// Bump the global text size by [delta] (e.g. ±0.1) and persist.
  Future<void> bumpMdScale(double delta) async {
    mdScale = double.parse((mdScale + delta).clamp(0.6, 3.0).toStringAsFixed(2));
    notifyListeners();
    await saveMdScale();
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String password,
    String? newApiKey,
    String? newModel,
    double? newTemperature,
  }) async {
    // Normalize: strip trailing slash.
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    api.baseUrl = url;
    api.password = password.trim();
    if (newApiKey != null) api.apiKey = newApiKey.trim();
    if (newModel != null) model = newModel;
    if (newTemperature != null) temperature = newTemperature;

    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', api.baseUrl);
    await p.setString('password', api.password);
    await p.setString('apiKey', api.apiKey);
    await p.setString('model', model);
    await p.setDouble('temperature', temperature);
    notifyListeners();
  }

  /// Live-update the markdown text scale during a pinch (no disk write).
  void previewMdScale(double v) {
    mdScale = v;
    notifyListeners();
  }

  /// Persist the markdown text scale (called when the pinch ends).
  Future<void> saveMdScale() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('mdScale', mdScale);
  }

  Future<void> setModel(String id) async {
    model = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('model', id);
    notifyListeners();
  }

  Future<void> setImagesModel(String id) async {
    imagesModel = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('imagesModel', id);
    notifyListeners();
  }

  Future<void> setScribePrefs({
    String? mode,
    String? artStyle,
    String? imageModel,
    bool? genImages,
  }) async {
    if (mode != null) scribeMode = mode;
    if (artStyle != null) scribeArtStyle = artStyle;
    if (imageModel != null) scribeImageModel = imageModel;
    if (genImages != null) scribeGenImages = genImages;
    final p = await SharedPreferences.getInstance();
    await p.setString('scribeMode', scribeMode);
    await p.setString('scribeArtStyle', scribeArtStyle);
    await p.setString('scribeImageModel', scribeImageModel);
    await p.setBool('scribeGenImages', scribeGenImages);
    notifyListeners();
  }

  /// Vision-capable models (for the Images tab describe picker).
  List<ModelInfo> get visionModels => models.where((m) => m.vision).toList();

  // ---- Books ----

  Future<void> refreshBooks() async {
    loadingBooks = true;
    booksError = null;
    notifyListeners();
    try {
      books = await api.listBooks();
    } catch (e) {
      booksError = e.toString();
    }
    loadingBooks = false;
    notifyListeners();
  }

  /// Upload an epub file; the server parses it and it lands in the shared DB.
  Future<Book> addBookFromFile(Uint8List bytes, String filename) async {
    final b = await api.uploadEpub(bytes, filename);
    await api.saveBook(b);
    await refreshBooks();
    return books.firstWhere((x) => x.bookId == b.bookId, orElse: () => b);
  }

  /// The library list rows are light (no text/segments/images/scribes). Fill
  /// the full record in place before reading, chatting or browsing images.
  Future<Book> ensureFullBook(Book b) async {
    if (b.fullLoaded) return b;
    final full = await api.getBook(b.bookId);
    final i = books.indexWhere((x) => x.bookId == b.bookId);
    if (i >= 0) books[i] = full;
    notifyListeners();
    return full;
  }

  Future<void> saveBook(Book b) async {
    await api.saveBook(b);
    notifyListeners();
  }

  Future<void> deleteBook(String bookId) async {
    await api.deleteBook(bookId);
    books.removeWhere((b) => b.bookId == bookId);
    notifyListeners();
  }

  /// Generate a concise 1–2 sentence AI summary for every chapter, grounded
  /// only in that chapter's text. Batched so long books stay under limits.
  /// Mirrors the web dashboard's summarizeChapters. Returns how many got one.
  Future<int> summarizeChapters(Book b,
      {void Function(String status)? onProgress}) async {
    if (b.chapters.isEmpty) return 0;
    if (b.segments.isEmpty) {
      throw ApiException('No text to summarize from.', 400);
    }
    final merged =
        b.chapters.map((c) => Map<String, dynamic>.from(c as Map)).toList();
    const batch = 12;
    var done = 0;
    for (var off = 0; off < merged.length; off += batch) {
      final end = (off + batch).clamp(0, merged.length);
      onProgress?.call('Summarizing ${off + 1}–$end of ${merged.length}…');
      final slice = <Map<String, dynamic>>[];
      for (var i = off; i < end; i++) {
        slice.add({'i': i, 'title': merged[i]['title'], 'text': b.chapterText(i, maxChars: 3500)});
      }
      final prompt =
          "For each chapter below, write a concise 1-2 sentence summary grounded ONLY in that chapter's text. "
          'Return STRICT JSON only: {"summaries":[{"i":0,"summary":"..."}]}. Use the given "i" values. No prose, no code fences.\n\n'
          '${slice.map((p) => 'Chapter ${p['i']} — ${p['title']}\nText: ${(p['text'] as String).isEmpty ? '(no text in range)' : p['text']}').join('\n\n')}';
      final resp = await api.chat(
        model: model,
        messages: [{'role': 'user', 'content': prompt}],
        temperature: 0.3,
      );
      final obj = _looseJson(resp.content);
      for (final s in (obj?['summaries'] as List? ?? [])) {
        final i = (s is Map ? s['i'] : null);
        if (i is int && i >= 0 && i < merged.length) {
          final sum = s['summary']?.toString() ?? '';
          if (sum.isNotEmpty) merged[i]['summary'] = sum;
        }
      }
    }
    b.chapters = merged;
    done = merged.where((c) => (c['summary'] ?? '').toString().isNotEmpty).length;
    await saveBook(b);
    return done;
  }

  // ---- Syntopical essays ----

  Future<void> refreshEssays() async {
    loadingEssays = true;
    essaysError = null;
    notifyListeners();
    try {
      essays = await api.listEssays();
    } catch (e) {
      essaysError = e.toString();
    }
    loadingEssays = false;
    notifyListeners();
  }

  // ---- Prompts ----

  Future<void> refreshPrompts() async {
    final defaults = await api.listDefaultPrompts();
    List<PromptTemplate> custom = [];
    try {
      custom = await api.listPrompts();
    } catch (_) {}
    // DB prompts override builtins with the same id (same merge as the web).
    final customIds = custom.map((p) => p.id).toSet();
    prompts = [
      ...defaults.where((d) => !customIds.contains(d.id)),
      ...custom,
    ];
    notifyListeners();
  }

  Future<void> savePrompt(PromptTemplate p) async {
    await api.savePrompt(p);
    await refreshPrompts();
  }

  Future<void> deletePrompt(String id) async {
    await api.deletePrompt(id);
    await refreshPrompts();
  }

  // ---- Models ----

  Future<void> refreshModels() async {
    try {
      models = await api.listModels();
      notifyListeners();
    } catch (_) {}
  }

  // ---- Chat (same system prompt as the web dashboard) ----

  Future<ChatResponse> askBook(Book b, List<ChatMessage> history,
      {void Function(String delta)? onDelta}) {
    final system = {
      'role': 'system',
      'content':
          "You are a helpful assistant answering questions about a specific book, using ONLY the book text provided. If the answer isn't in the text, say so.\n\nBook title: ${b.title}\nAuthor: ${b.author ?? 'unknown'}\n\nBOOK TEXT:\n${b.text}",
    };
    return api.chat(
      model: model,
      messages: [
        system,
        ...history.map((m) => {'role': m.role, 'content': m.content}),
      ],
      temperature: temperature,
      onDelta: onDelta,
    );
  }

  /// Run a standardized prompt. [chapterScope] = null → whole book, otherwise
  /// the selected chapter indexes (booktext becomes "## title\n\ntext" blocks,
  /// same as the web).
  Future<ChatResponse> runPrompt(Book b, PromptTemplate p,
      {List<int>? chapterScope, void Function(String delta)? onDelta}) {
    String booktext;
    if (chapterScope == null || chapterScope.isEmpty) {
      booktext = b.text;
    } else {
      booktext = chapterScope.map((i) {
        final title =
            ((b.chapters[i] as Map)['title'] ?? 'Chapter ${i + 1}').toString();
        return '## $title\n\n${b.chapterText(i)}';
      }).join('\n\n');
    }
    final filled = p.fill(
      title: b.title ?? '',
      author: b.author ?? '',
      booktext: booktext,
    );
    return api.chat(
      model: model,
      messages: [
        {'role': 'user', 'content': filled},
      ],
      temperature: temperature,
      onDelta: onDelta,
    );
  }
}
