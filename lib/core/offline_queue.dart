import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Requests made without internet (attendance, bus scans, gate scans) are kept on the
/// phone and sent in order as soon as the server can be reached again.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(this._api);

  final ApiClient _api;
  static const _key = 'offline_queue';
  List<Map<String, dynamic>> _items = [];
  bool _flushing = false;

  int get pending => _items.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _items = raw == null ? [] : List<Map<String, dynamic>>.from((jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_items));
    notifyListeners();
  }

  /// Try now; if the server cannot be reached, keep it for later.
  /// Returns the server's answer, or null when the request was queued.
  Future<dynamic> postOrQueue(String path, Map<String, dynamic> body) async {
    try {
      return (await _api.post(path, body)) ?? true;
    } on ApiException catch (e) {
      if (!e.offline) rethrow;
      _items.add({'path': path, 'body': body});
      await _save();
      return null;
    }
  }

  /// Same, when the answer is not needed: true = sent, false = queued.
  Future<bool> sendOrQueue(String path, Map<String, dynamic> body) async => (await postOrQueue(path, body)) != null;

  /// Send everything that is waiting. Safe to call often.
  Future<void> flush() async {
    if (_flushing || _items.isEmpty) return;
    _flushing = true;
    try {
      while (_items.isNotEmpty) {
        final item = _items.first;
        try {
          await _api.post(item['path'] as String, Map<String, dynamic>.from(item['body'] as Map));
        } on ApiException catch (e) {
          if (e.offline) break; // still no internet: try again later
          // The server refused it (for example the trip has ended): nothing more to do with it.
        }
        _items.removeAt(0);
        await _save();
      }
    } finally {
      _flushing = false;
    }
  }
}
