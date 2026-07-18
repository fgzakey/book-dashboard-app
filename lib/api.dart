import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Client for the Book Dashboard backend (the Hugging Face Space).
///
/// Auth: the dashboard's middleware accepts a `book_auth=<password>` cookie, so
/// after validating the password once via POST /api/login we simply attach
/// that cookie header to every request — no cookie jar needed.
class ApiClient {
  String baseUrl; // e.g. https://<user>-<space>.hf.space  (no trailing slash)
  String password;

  ApiClient({this.baseUrl = '', this.password = ''});

  // The server URL ships prefilled, so "configured" means the password has
  // been entered too — first run lands on Settings asking only for it.
  bool get configured => baseUrl.isNotEmpty && password.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (password.isNotEmpty) 'Cookie': 'book_auth=$password',
      };

  Never _fail(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['error'] != null) msg = j['error'].toString();
    } catch (_) {}
    throw ApiException(msg, res.statusCode);
  }

  Map<String, dynamic> _json(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  /// Validates the password. Throws on failure.
  Future<void> login() async {
    final res = await http.post(
      _uri('/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode != 200) _fail(res);
  }

  // ---- Epub upload ----

  /// Uploads an .epub and returns the parsed book (metadata, chapters, text…).
  /// The server does all the parsing; nothing is sent to any AI model here.
  Future<Book> uploadEpub(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri('/api/epub'));
    if (password.isNotEmpty) req.headers['Cookie'] = 'book_auth=$password';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(streamed);
    final j = _json(res);
    return Book.fromJson(Map<String, dynamic>.from(j['book']));
  }

  // ---- Books ----

  Future<List<Book>> listBooks() async {
    final res = await http.get(_uri('/api/db/books'), headers: _headers);
    final j = _json(res);
    return ((j['books'] as List?) ?? [])
        .map((b) => Book.fromJson(Map<String, dynamic>.from(b)))
        .toList();
  }

  /// The list rows exclude heavy fields (text, segments) — this fetches the
  /// full record for reading and chat context.
  Future<Book> getBook(String bookId) async {
    final res = await http.get(_uri('/api/db/books', {'id': bookId}),
        headers: _headers);
    final j = _json(res);
    if (j['book'] == null) throw ApiException('Book not found.', 404);
    return Book.fromJson(Map<String, dynamic>.from(j['book']));
  }

  Future<void> saveBook(Book b) async {
    final res = await http.post(_uri('/api/db/books'),
        headers: _headers, body: jsonEncode(b.toJson()));
    _json(res);
  }

  Future<void> deleteBook(String bookId) async {
    final res = await http.delete(_uri('/api/db/books', {'id': bookId}),
        headers: _headers);
    _json(res);
  }

  // ---- Prompts ----

  Future<List<PromptTemplate>> listPrompts() async {
    final res = await http.get(_uri('/api/db/prompts'), headers: _headers);
    final j = _json(res);
    return ((j['prompts'] as List?) ?? [])
        .map((p) => PromptTemplate.fromJson(Map<String, dynamic>.from(p)))
        .toList();
  }

  /// Built-in default prompts (served by /api/prompts/defaults so builtins
  /// stay in one place — lib/prompts.js). Returns [] if unreachable.
  Future<List<PromptTemplate>> listDefaultPrompts() async {
    try {
      final res = await http.get(_uri('/api/prompts/defaults'), headers: _headers);
      if (res.statusCode != 200) return [];
      final j = _json(res);
      return ((j['prompts'] as List?) ?? [])
          .map((p) => PromptTemplate.fromJson(Map<String, dynamic>.from(p)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePrompt(PromptTemplate p) async {
    final res = await http.post(_uri('/api/db/prompts'),
        headers: _headers, body: jsonEncode(p.toJson()));
    _json(res);
  }

  Future<void> deletePrompt(String id) async {
    final res = await http.delete(_uri('/api/db/prompts', {'id': id}),
        headers: _headers);
    _json(res);
  }

  // ---- Results ----

  Future<List<SavedResult>> listResults({String query = '', String? bookId}) async {
    final res = await http.get(
        _uri('/api/db/results', {
          if (bookId != null) 'bookId': bookId,
          if (query.isNotEmpty) 'q': query,
        }),
        headers: _headers);
    final j = _json(res);
    return ((j['results'] as List?) ?? [])
        .map((r) => SavedResult.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> saveResult({
    required String content,
    String? bookId,
    String? bookTitle,
    String? promptName,
    String? scope,
    String? model,
    String? cost,
  }) async {
    final res = await http.post(_uri('/api/db/results'),
        headers: _headers,
        body: jsonEncode({
          'content': content,
          'bookId': bookId,
          'bookTitle': bookTitle,
          'promptName': promptName,
          'scope': scope,
          'model': model,
          'cost': cost,
        }));
    _json(res);
  }

  // ---- Models & chat ----

  Future<List<ModelInfo>> listModels() async {
    final res = await http.get(_uri('/api/models'), headers: _headers);
    final j = _json(res);
    return ((j['models'] as List?) ?? [])
        .map((m) => ModelInfo.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<ChatResponse> chat({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.4,
  }) async {
    final res = await http
        .post(_uri('/api/chat'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': temperature,
            }))
        .timeout(const Duration(minutes: 5));
    final j = _json(res);
    return ChatResponse(
      content: j['content'] as String? ?? '',
      model: j['model'] as String?,
      usage: j['usage'] == null ? null : Map<String, dynamic>.from(j['usage']),
    );
  }
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}
