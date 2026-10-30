import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'i18n.dart';
import 'push.dart';
import 'sos_alarm.dart';

/// One login returned by the server (a mobile number can have a login in more than one school).
class Account {
  Account({required this.token, required this.user, required this.school, this.features});

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    token: json['token'] as String,
    user: Map<String, dynamic>.from(json['user'] as Map),
    school: json['school'] == null ? null : Map<String, dynamic>.from(json['school'] as Map),
    features: json['features'] == null ? null : List<String>.from(json['features'] as List),
  );

  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic>? school;
  final List<String>? features;

  List<String> get roles => List<String>.from(user['roles'] as List? ?? const []);

  /// Can this login use the app at all (parent, staff or driver)? Accountants etc. use the website.
  bool get allowedHere => AppConfig.modesFor(roles).isNotEmpty;
}

/// Who is signed in, which server we talk to, and the chosen language.
class Session extends ChangeNotifier {
  Session() {
    api = ApiClient(baseUrl: AppConfig.defaultApiUrl, onUnauthorized: _expired);
  }

  late final ApiClient api;
  static const _secure = FlutterSecureStorage();
  late SharedPreferences prefs;

  bool ready = false;
  Map<String, dynamic>? user;
  Map<String, dynamic>? school;

  /// Features the school has switched on (set by the super admin). Null = unknown, show everything.
  List<String>? features;

  bool get signedIn => api.token != null && user != null;
  String get userName => (user?['name'] as String?) ?? '';
  String get schoolName => (school?['name'] as String?) ?? '';
  String get serverUrl => api.baseUrl;
  List<String> get roles => List<String>.from(user?['roles'] as List? ?? const []);

  /// Modes this login can use (more than one = a "Use the app as" switch in Profile).
  List<AppKind> get modes => AppConfig.modesFor(roles);
  AppKind get mode => AppConfig.kind;

  Future<void> setMode(AppKind mode) async {
    if (!modes.contains(mode)) return;
    AppConfig.kind = mode;
    await prefs.setString('mode', mode.name);
    notifyListeners();
  }

  /// The saved mode if this login may still use it, else the best one for its roles.
  void _applyMode() {
    final saved = prefs.getString('mode');
    final choice = modes.where((m) => m.name == saved);
    AppConfig.kind = choice.isNotEmpty ? choice.first : AppConfig.defaultMode(roles);
  }

  /// Is this part of the app switched on for the school? (fees, transport, homework, exams, chat ...)
  bool has(String feature) => features == null || features!.contains(feature);

  /// Signed in with the password printed by the school: must choose their own first.
  bool get mustChangePassword => user?['must_change_password'] == true;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString('server_url') ?? AppConfig.defaultApiUrl;
    I18n.locale = prefs.getString('locale') ?? 'en';

    try {
      api.token = await _secure.read(key: 'token');
    } catch (_) {
      api.token = null;
    }

    final savedUser = prefs.getString('user');
    final savedSchool = prefs.getString('school');
    if (api.token != null && savedUser != null) {
      user = jsonDecode(savedUser) as Map<String, dynamic>;
      school = savedSchool == null ? null : jsonDecode(savedSchool) as Map<String, dynamic>;
      final savedFeatures = prefs.getString('features');
      features = savedFeatures == null ? null : List<String>.from(jsonDecode(savedFeatures) as List);
    } else {
      api.token = null;
    }

    // Developer preview only: --dart-define=PREVIEW_TOKEN=... opens the app already signed in,
    // so screens can be checked in a browser. Empty in every normal build.
    const previewToken = String.fromEnvironment('PREVIEW_TOKEN');
    if (previewToken.isNotEmpty) {
      try {
        api.token = previewToken;
        final me = await api.get('/me') as Map<String, dynamic>;
        user = Map<String, dynamic>.from(me['user'] as Map);
        school = me['school'] == null ? null : Map<String, dynamic>.from(me['school'] as Map);
      } catch (_) {
        api.token = null;
      }
    }

    if (user != null) _applyMode();
    ready = true;
    notifyListeners();
  }

  /// Fetches the latest profile and feature switches (the school may have changed them).
  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      final me = await api.get('/me') as Map<String, dynamic>;
      user = Map<String, dynamic>.from(me['user'] as Map);
      school = me['school'] == null ? null : Map<String, dynamic>.from(me['school'] as Map);
      features = me['features'] == null ? null : List<String>.from(me['features'] as List);
      // Roles may have changed at school: keep the mode valid.
      if (!modes.contains(AppConfig.kind)) _applyMode();
      await prefs.setString('user', jsonEncode(user));
      if (school != null) await prefs.setString('school', jsonEncode(school));
      if (features != null) await prefs.setString('features', jsonEncode(features));
      notifyListeners();
      SosWatch.start(this);
    } catch (_) {
      // Offline: keep what was saved.
    }
  }

  Future<void> setServerUrl(String url) async {
    var clean = url.trim();
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    api.baseUrl = clean;
    await prefs.setString('server_url', clean);
    notifyListeners();
  }

  /// Sign in with login ID, email or mobile number and password (no SMS).
  Future<List<Account>> passwordLogin(String login, String password) async {
    final data = await api.post('/auth/login', {'login': login, 'password': password, 'device_name': AppConfig.appName});
    return _accounts(data);
  }

  Future<void> changePassword(String current, String password) async {
    final data = await api.put('/me/password', {'current_password': current, 'password': password}) as Map<String, dynamic>;
    user = Map<String, dynamic>.from(data['user'] as Map);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  List<Account> _accounts(dynamic data) {
    final list = ((data as Map<String, dynamic>)['accounts'] as List).map((a) => Account.fromJson(Map<String, dynamic>.from(a as Map))).toList();
    final allowed = list.where((a) => a.allowedHere).toList();
    if (allowed.isEmpty) {
      throw ApiException('This login is for the school website, not the app. Please sign in on the website.');
    }
    return allowed;
  }

  Future<void> useAccount(Account account) async {
    api.token = account.token;
    user = account.user;
    school = account.school;
    features = account.features;
    if (features != null) await prefs.setString('features', jsonEncode(features));
    await _secure.write(key: 'token', value: account.token);
    await prefs.setString('user', jsonEncode(account.user));
    if (account.school != null) await prefs.setString('school', jsonEncode(account.school));
    _applyMode();

    final serverLocale = account.user['locale'] as String?;
    if (serverLocale != null && I18n.names.containsKey(serverLocale)) {
      I18n.locale = serverLocale;
      await prefs.setString('locale', serverLocale);
    }
    notifyListeners();
    unawaited(Push.start(this));
    SosWatch.start(this);
  }

  Future<void> setLocale(String locale) async {
    I18n.locale = locale;
    await prefs.setString('locale', locale);
    notifyListeners();
    try {
      // Alerts from the school then arrive in this language too.
      await api.put('/me/locale', {'locale': locale});
    } catch (_) {
      // Saved on the phone; the server will get it next time.
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout', {if (Push.token != null) 'device_token': Push.token});
    } catch (_) {
      // Signing out on the phone must always work, even offline.
    }
    await Push.stop();
    SosWatch.stop();
    await _clear();
  }

  void _expired() {
    if (signedIn) _clear();
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    school = null;
    features = null;
    await prefs.remove('features');
    // The next person on this phone starts in their own default mode.
    await prefs.remove('mode');
    AppConfig.kind = AppKind.parent;
    await _secure.delete(key: 'token');
    await prefs.remove('user');
    await prefs.remove('school');
    notifyListeners();
  }
}
