import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Prefilled server address — the deployed Space. Only the app password is
/// needed on first run; override the URL in Settings to point elsewhere.
const String kDefaultServerUrl = 'https://fgza-book-dashboard.hf.space';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  bool loadedPrefs = false;
  String model = 'google/gemini-2.5-flash';
  double temperature = 0.4;

  List<Book> books = [];
  List<PromptTemplate> prompts = []; // builtins + custom, builtins first
  List<ModelInfo> models = [];

  bool loadingBooks = false;
  String? booksError;

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    final savedUrl = p.getString('baseUrl');
    api.baseUrl = (savedUrl == null || savedUrl.isEmpty) ? kDefaultServerUrl : savedUrl;
    api.password = p.getString('password') ?? '';
    model = p.getString('model') ?? model;
    temperature = p.getDouble('temperature') ?? 0.4;
    loadedPrefs = true;
    notifyListeners();
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String password,
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
    if (newModel != null) model = newModel;
    if (newTemperature != null) temperature = newTemperature;

    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', api.baseUrl);
    await p.setString('password', api.password);
    await p.setString('model', model);
    await p.setDouble('temperature', temperature);
    notifyListeners();
  }

  Future<void> setModel(String id) async {
    model = id;
    final p = await SharedPreferences.getInstance();
    await p.setString('model', id);
    notifyListeners();
  }

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

  /// The library list rows are light (no text/segments). Fill the full record
  /// in place before reading or chatting.
  Future<Book> ensureFullBook(Book b) async {
    if (b.text.isNotEmpty) return b;
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

  Future<ChatResponse> askBook(Book b, List<ChatMessage> history) {
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
    );
  }

  Future<ChatResponse> runPrompt(Book b, PromptTemplate p) {
    final filled = p.fill(
      title: b.title ?? '',
      author: b.author ?? '',
      booktext: b.text,
    );
    return api.chat(
      model: model,
      messages: [
        {'role': 'user', 'content': filled},
      ],
      temperature: temperature,
    );
  }
}
