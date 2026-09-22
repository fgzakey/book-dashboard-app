import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Client for the Phil's Library backend (the Hugging Face Space).
///
/// Auth: the dashboard's middleware accepts a `book_auth=<password>` cookie, so
/// after validating the password once via POST /api/login we simply attach
/// that cookie header to every request — no cookie jar needed.
class ApiClient {
  String baseUrl; // e.g. https://<user>-<space>.hf.space  (no trailing slash)
  String password;

  /// Optional OpenRouter key. When the Space has OPENROUTER_API_KEY set as a
  /// secret this can stay empty — the server key wins. Sent in request bodies
  /// exactly like the web client does.
  String apiKey;

  /// Optional Google Gemini API key. When provided, requests to Google models
  /// bypass OpenRouter and route directly to Google AI Studio with zero fees.
  String geminiApiKey;

  ApiClient({
    this.baseUrl = '',
    this.password = '',
    this.apiKey = '',
    this.geminiApiKey = '',
  });

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
    // The HF Space proxy answers timeouts with an HTML error page — surface
    // that as a readable error instead of a JSON parse crash.
    try {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    } catch (_) {
      throw ApiException(
          'Server returned a non-JSON response (likely a gateway timeout on the Space). Try again or narrow the scope.',
          res.statusCode);
    }
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

  /// Uploads an .epub and returns the parsed book (metadata, chapters, text,
  /// images…). The server does all the parsing; nothing goes to an AI model.
  Future<Book> uploadEpub(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri('/api/epub'));
    if (password.isNotEmpty) req.headers['Cookie'] = 'book_auth=$password';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
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

  /// The list rows exclude heavy fields (text, segments, images, scribes) —
  /// this fetches the full record for reading, chat, images and boards.
  Future<Book> getBook(String bookId) async {
    final res = await http
        .get(_uri('/api/db/books', {'id': bookId}), headers: _headers)
        .timeout(const Duration(minutes: 3));
    final j = _json(res);
    if (j['book'] == null) throw ApiException('Book not found.', 404);
    return Book.fromJson(Map<String, dynamic>.from(j['book']));
  }

  Future<void> saveBook(Book b) async {
    final res = await http
        .post(_uri('/api/db/books'),
            headers: _headers, body: jsonEncode(b.toJson()))
        .timeout(const Duration(minutes: 3));
    _json(res);
  }

  Future<void> deleteBook(String bookId) async {
    final res = await http.delete(_uri('/api/db/books', {'id': bookId}),
        headers: _headers);
    _json(res);
  }

  /// Stamps `last_opened_at` on the server and returns the new epoch ms.
  Future<int?> touchBook(String bookId) async {
    final res = await http.patch(_uri('/api/db/books', {'touch': bookId}),
        headers: _headers);
    final j = _json(res);
    return (j['openedAt'] as num?)?.toInt();
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

  // ---- Syntopical essays ----

  Future<List<Essay>> listEssays() async {
    final res = await http.get(_uri('/api/essays'), headers: _headers);
    final j = _json(res);
    return ((j['essays'] as List?) ?? [])
        .map((e) => Essay.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---- Results ----

  Future<List<SavedResult>> listResults({String query = '', String? bookId}) async {
    final res = await http.get(
        _uri('/api/db/results', {
          // Dart 3.10 null-aware map element: the `?` goes on the VALUE, so
          // the entry is dropped when bookId is null.
          'bookId': ?bookId,
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

  Future<SavedResult> getResult(dynamic id) async {
    final res = await http.get(_uri('/api/db/results', {'id': '$id'}),
        headers: _headers);
    final j = _json(res);
    final r = j['result'];
    if (r == null) throw ApiException('Result not found.', 404);
    return SavedResult.fromJson(Map<String, dynamic>.from(r));
  }

  /// Downloads/decodes the full audio bytes (.mp3) for a given result row.
  Future<Uint8List?> fetchResultAudioBytes(dynamic id) async {
    final r = await getResult(id);
    final audioStr = r.audio;
    if (audioStr == null || audioStr.isEmpty) return null;
    if (audioStr.startsWith('data:')) {
      final comma = audioStr.indexOf(',');
      if (comma != -1) {
        return base64Decode(audioStr.substring(comma + 1));
      }
    }
    return base64Decode(audioStr);
  }

  Future<void> deleteResult(dynamic id) async {
    final res = await http.delete(
        _uri('/api/db/results', {'id': '$id'}),
        headers: _headers);
    _json(res);
  }

  Future<void> deleteBookResults(String bookId, {bool includeGraph = true}) async {
    final res = await http.delete(
        _uri('/api/db/results', {
          'bookId': bookId,
          if (includeGraph) 'includeGraph': '1',
        }),
        headers: _headers);
    _json(res);
  }

  // ---- Models & chat ----

  Future<List<ModelInfo>> listModels({bool refresh = false}) async {
    final res = await http.get(
        _uri('/api/models', {if (refresh) 'refresh': '1'}),
        headers: _headers);
    final j = _json(res);
    return ((j['models'] as List?) ?? [])
        .map((m) => ModelInfo.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Streaming chat — mirrors the web client. The server proxies OpenRouter's
  /// SSE stream through, which enables live output AND keeps the HF Space
  /// proxy from killing long-silent big-book requests. [onDelta] receives each
  /// content fragment as it arrives.
  Future<ChatResponse> chat({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.4,
    void Function(String delta)? onDelta,
  }) async {
    final req = http.Request('POST', _uri('/api/chat'));
    req.headers.addAll(_headers);
    req.body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'stream': true,
      if (apiKey.isNotEmpty) 'apiKey': apiKey,
      if (geminiApiKey.isNotEmpty) 'geminiApiKey': geminiApiKey,
    });

    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(minutes: 2));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = await res.stream.bytesToString();
        String msg = 'HTTP ${res.statusCode}';
        try {
          final j = jsonDecode(body);
          if (j is Map && j['error'] != null) msg = j['error'].toString();
        } catch (_) {}
        throw ApiException(msg, res.statusCode);
      }

      final content = StringBuffer();
      Map<String, dynamic>? usage;
      String? usedModel;
      var carry = '';

      await for (final chunk in res.stream
          .transform(utf8.decoder)
          .timeout(const Duration(minutes: 30))) {
        carry += chunk;
        while (true) {
          final nl = carry.indexOf('\n');
          if (nl < 0) break;
          final line = carry.substring(0, nl).trim();
          carry = carry.substring(nl + 1);
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          try {
            final j = jsonDecode(data);
            if (j is! Map) continue;
            final delta = ((j['choices'] as List?)?.firstOrNull
                as Map?)?['delta'] as Map?;
            final piece = delta?['content'];
            if (piece is String && piece.isNotEmpty) {
              content.write(piece);
              onDelta?.call(piece);
            }
            if (j['usage'] != null) {
              usage = Map<String, dynamic>.from(j['usage']);
            }
            if (j['model'] != null) usedModel = j['model'].toString();
          } catch (_) {
            // Ignore malformed keep-alive/comment lines.
          }
        }
      }

      if (content.isEmpty) {
        throw ApiException('The model returned an empty response.', 502);
      }
      return ChatResponse(
          content: content.toString(), model: usedModel ?? model, usage: usage);
    } finally {
      client.close();
    }
  }

  // ---- Images & Figures ----

  /// Sends epub images to a vision model for cataloging. [images] entries:
  /// {id, dataUrl, chapterTitle}. Returns {entries, errors, usage, model}.
  Future<Map<String, dynamic>> describeImages({
    required List<Map<String, dynamic>> images,
    required String model,
    String? title,
    String? author,
    String? prompt,
  }) async {
    final res = await http
        .post(_uri('/api/images/describe'),
            headers: _headers,
            body: jsonEncode({
              'images': images,
              'model': model,
              'title': title,
              'author': author,
              if (prompt != null && prompt.trim().isNotEmpty) 'prompt': prompt,
              if (apiKey.isNotEmpty) 'apiKey': apiKey,
              if (geminiApiKey.isNotEmpty) 'geminiApiKey': geminiApiKey,
            }))
        .timeout(const Duration(minutes: 6));
    return _json(res);
  }

  /// Builds the "Images & Figures" PDF on the server and returns the bytes.
  Future<Uint8List> imagesPdf({
    required String title,
    String? author,
    String? model,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await http
        .post(_uri('/api/images/pdf'),
            headers: _headers,
            body: jsonEncode({
              'title': title,
              'author': author,
              'model': model,
              'items': items,
            }))
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) _fail(res);
    return res.bodyBytes;
  }

  /// Faithful ~2x AI upscale of one image. Returns the new data URL.
  Future<String> upscaleImage(String dataUrl, {String? imageModel}) async {
    final res = await http
        .post(_uri('/api/upscale'),
            headers: _headers,
            body: jsonEncode({
              'image': dataUrl,
              if (imageModel != null && imageModel.isNotEmpty)
                'imageModel': imageModel,
              if (apiKey.isNotEmpty) 'apiKey': apiKey,
              if (geminiApiKey.isNotEmpty) 'geminiApiKey': geminiApiKey,
            }))
        .timeout(const Duration(minutes: 3));
    final j = _json(res);
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) throw ApiException('No image returned.', 502);
    return url;
  }

  // ---- Visual Scribe ----

  /// Step 1: design the board spec (fast, no images). Same request the web
  /// client makes. Returns {spec, usage, model, mode, artStyle}.
  Future<Map<String, dynamic>> scribeSpec({
    required String booktext,
    required String title,
    String author = '',
    required String textModel,
    required String mode,
    required String artStyle,
    double temperature = 0.4,
  }) async {
    final res = await http
        .post(_uri('/api/scribe'),
            headers: _headers,
            body: jsonEncode({
              'booktext': booktext,
              'title': title,
              'author': author,
              'textModel': textModel,
              'generateImages': false,
              'mode': mode,
              'artStyle': artStyle,
              'temperature': temperature,
              if (apiKey.isNotEmpty) 'apiKey': apiKey,
              if (geminiApiKey.isNotEmpty) 'geminiApiKey': geminiApiKey,
            }))
        .timeout(const Duration(minutes: 6));
    return _json(res);
  }

  /// Step 2: paint one illustration per request (short calls keep the Space
  /// proxy happy). Returns the image data URL.
  Future<String> scribeImage({
    required String imagePrompt,
    String imageContext = '',
    required String artStyle,
    String? imageModel,
  }) async {
    final res = await http
        .post(_uri('/api/scribe'),
            headers: _headers,
            body: jsonEncode({
              'imagePrompt': imagePrompt,
              'imageContext': imageContext,
              'artStyle': artStyle,
              if (imageModel != null && imageModel.isNotEmpty)
                'imageModel': imageModel,
              if (apiKey.isNotEmpty) 'apiKey': apiKey,
              if (geminiApiKey.isNotEmpty) 'geminiApiKey': geminiApiKey,
            }))
        .timeout(const Duration(minutes: 4));
    final j = _json(res);
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) throw ApiException('No image returned.', 502);
    return url;
  }

  // ---- Workspaces / Databases ----

  Future<WorkspacesResponse> listWorkspaces() async {
    final res = await http.get(_uri('/api/db/workspaces'), headers: _headers);
    return WorkspacesResponse.fromJson(_json(res));
  }

  Future<void> switchWorkspace(String name, {String? owner}) async {
    final res = await http.post(_uri('/api/db/workspaces'),
        headers: _headers,
        body: jsonEncode({
          'action': 'switch',
          'name': name,
          'owner': ?owner,
        }));
    _json(res);
  }

  // ---- Mnemonic scenes ----

  Future<List<MnemonicSource>> listMnemonicSources() async {
    final res = await http.get(_uri('/api/mnemonic', {'sources': '1'}),
        headers: _headers);
    final j = _json(res);
    return ((j['sources'] as List?) ?? [])
        .map((s) => MnemonicSource.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  Future<List<MnemonicScene>> listMnemonicScenes(
      String sourceKind, String sourceId) async {
    final res = await http.get(
        _uri('/api/mnemonic', {'sourceKind': sourceKind, 'sourceId': sourceId}),
        headers: _headers);
    final j = _json(res);
    return ((j['images'] as List?) ?? [])
        .map((m) => MnemonicScene.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<MnemonicScene> getMnemonicScene(dynamic id) async {
    final res = await http
        .get(_uri('/api/mnemonic', {'id': '$id'}), headers: _headers)
        .timeout(const Duration(minutes: 3));
    final j = _json(res);
    final row = j['image'];
    if (row == null) throw ApiException('Scene not found.', 404);
    return MnemonicScene.fromJson(Map<String, dynamic>.from(row));
  }
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, this.status);
  @override
  String toString() => message;
}
