import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// An error with a message that is safe to show to the user.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.offline = false, this.fieldErrors = const {}});

  final String message;
  final int? status;

  /// True when the server could not be reached at all (no internet, server down).
  final bool offline;
  final Map<String, dynamic> fieldErrors;

  @override
  String toString() => message;
}

/// A file to send in a multipart request.
class UploadFile {
  UploadFile(this.field, this.name, this.bytes);

  final String field;
  final String name;
  final Uint8List bytes;
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, this.onUnauthorized});

  String baseUrl;
  String? token;

  /// Called when the server says the login is no longer valid.
  void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 25);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final clean = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final uri = Uri.parse(path.startsWith('http') ? path : '$clean/api/v1$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    });
  }

  Map<String, String> get authHeaders => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(() => http.get(_uri(path, query), headers: authHeaders));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _json('POST', path, body);

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _json('PUT', path, body);

  Future<dynamic> delete(String path) => _json('DELETE', path, null);

  Future<dynamic> _json(String method, String path, Map<String, dynamic>? body) {
    return _send(() async {
      final request = http.Request(method, _uri(path))
        ..headers.addAll({...authHeaders, 'Content-Type': 'application/json'})
        ..body = jsonEncode(body ?? {});
      return http.Response.fromStream(await request.send());
    });
  }

  Future<dynamic> upload(String path, {Map<String, String> fields = const {}, List<UploadFile> files = const []}) {
    return _send(() async {
      final request = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(authHeaders)
        ..fields.addAll(fields);
      for (final file in files) {
        request.files.add(http.MultipartFile.fromBytes(file.field, file.bytes, filename: file.name));
      }
      return http.Response.fromStream(await request.send());
    }, timeout: const Duration(seconds: 90));
  }

  /// Raw bytes of a protected file (receipt PDF, photo).
  Future<Uint8List> download(String url) async {
    try {
      final response = await http.get(_uri(url), headers: authHeaders).timeout(const Duration(seconds: 60));
      if (response.statusCode >= 400) throw ApiException('Could not download the file.', status: response.statusCode);
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No internet connection. Please try again.', offline: true);
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() run, {Duration timeout = _timeout}) async {
    http.Response response;
    try {
      response = await run().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Please check your internet and try again.', offline: true);
    } on SocketException {
      throw ApiException('No internet connection. Please try again.', offline: true);
    } on http.ClientException {
      throw ApiException('Could not reach the school server. Please check your internet.', offline: true);
    }

    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    if (response.statusCode == 401) onUnauthorized?.call();

    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final errors = map['errors'] is Map<String, dynamic> ? map['errors'] as Map<String, dynamic> : const <String, dynamic>{};
    var message = (map['message'] as String?) ?? '';
    if (errors.isNotEmpty) {
      final first = errors.values.first;
      message = first is List && first.isNotEmpty ? '${first.first}' : message;
    }
    if (message.isEmpty || response.statusCode >= 500) {
      message = switch (response.statusCode) {
        401 => 'Please sign in again.',
        403 => 'You do not have access to this.',
        404 => 'This was not found.',
        429 => 'Too many attempts. Please wait a minute and try again.',
        _ => 'Something went wrong on the server. Please try again.',
      };
    }
    throw ApiException(message, status: response.statusCode, fieldErrors: errors);
  }
}
