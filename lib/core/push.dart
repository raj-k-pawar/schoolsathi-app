import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_links.dart';
import 'common_screens.dart';
import 'sos_alarm.dart';
import 'session.dart';

/// Push notifications (Firebase Cloud Messaging, free).
///
/// The Firebase settings come from the school server (/app-config), so push can be switched on
/// for apps that are already installed. They are also saved on the phone, where the Android
/// start-up code (SchoolSathiApplication.kt) uses them to show notifications while the app is closed.
/// If the server has no Firebase settings, push simply stays off and alerts are still in the app inbox.
class Push {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final _local = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel('school_alerts', 'School alerts', description: 'Attendance, bus, fees, homework and messages from the school', importance: Importance.high);

  // SOS from a bus: maximum importance and the siren sound (android/app/src/main/res/raw/siren.wav).
  static const _sosChannel = AndroidNotificationChannel(
    'sos_alerts',
    'SOS alarms',
    description: 'SOS from a school bus',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('siren'),
  );

  static bool _listening = false;
  static String? _token;
  static Session? _session;

  /// Starts push for the signed-in user. Safe to call more than once; never throws.
  static Future<void> start(Session session) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _session = session;
    try {
      final options = await _options(session);
      if (options == null) return;

      try {
        await Firebase.initializeApp(options: options);
      } on FirebaseException catch (e) {
        // Settings changed on the server: the running app keeps the old ones until the next start.
        if (e.code != 'duplicate-app') rethrow;
      }

      final messaging = FirebaseMessaging.instance;
      if (!_listening) {
        _listening = true;
        await _local.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
          onDidReceiveNotificationResponse: (response) => _openFromPayload(response.payload),
        );
        final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(_channel);
        await android?.createNotificationChannel(_sosChannel);

        // While the app is open Android does not show the notification itself, so show it here.
        FirebaseMessaging.onMessage.listen(_showInApp);
        // Tapped a notification while the app was in the background / closed.
        FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
        final initial = await messaging.getInitialMessage();
        if (initial != null) _openMessage(initial);

        // The classic FCM registration token is what the server's FCM HTTP v1 "token" target expects.
        // The newer register()/onRegistered API gives an installation ID instead, so it is not used yet.
        // ignore: deprecated_member_use
        messaging.onTokenRefresh.listen((token) {
          _token = token;
          _register(token);
        });
      }

      // Android 13+ asks the user once.
      await messaging.requestPermission();
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) {
        _token = token;
        await _register(token);
      }
    } catch (e) {
      debugPrint('Push notifications not started: $e');
    }
  }

  /// The token to remove from the server when signing out.
  static String? get token => _token;

  /// After sign-out this phone should get no more notifications for that user.
  static Future<void> stop() async {
    if (_token == null) return;
    _token = null;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Not started or offline: the server drops dead tokens by itself.
    }
  }

  static Future<FirebaseOptions?> _options(Session session) async {
    Map<String, dynamic>? config;
    try {
      final data = await session.api.get('/app-config', query: {'app': 'parent'} /* the one Android app, com.schoolsathi.app */) as Map<String, dynamic>;
      config = data['firebase'] == null ? null : Map<String, dynamic>.from(data['firebase'] as Map);
      if (config == null) {
        await session.prefs.remove('firebase_options');
      } else {
        await session.prefs.setString('firebase_options', jsonEncode(config));
      }
    } catch (_) {
      // Offline: use what was saved last time.
      final saved = session.prefs.getString('firebase_options');
      config = saved == null ? null : jsonDecode(saved) as Map<String, dynamic>;
    }
    if (config == null) return null;

    return FirebaseOptions(apiKey: config['api_key'] as String, appId: config['app_id'] as String, messagingSenderId: config['sender_id'] as String, projectId: config['project_id'] as String);
  }

  static Future<void> _register(String token) async {
    final session = _session;
    if (session == null || !session.signedIn) return;
    try {
      await session.api.post('/devices', {'token': token, 'platform': 'android'});
    } catch (_) {
      // Tried again at the next app start.
    }
  }

  static Future<void> _showInApp(RemoteMessage message) async {
    final type = message.data['type'] as String? ?? '';
    if (type.startsWith('bus.sos')) {
      // SOS raised or answered: the full-screen alarm starts or stops at once.
      unawaited(SosWatch.check());
      if (type != 'bus.sos_handled') return;
    }
    final note = message.notification;
    if (note == null) return;
    await _local.show(
      id: message.hashCode & 0x7fffffff,
      title: note.title,
      body: note.body,
      payload: jsonEncode({...message.data, 'title': note.title, 'body': note.body}),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          styleInformation: BigTextStyleInformation(note.body ?? ''),
        ),
      ),
    );
  }

  static void _openMessage(RemoteMessage message) => _open({...message.data, 'title': message.notification?.title, 'body': message.notification?.body});

  static void _openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return _open(const {});
    try {
      _open(Map<String, dynamic>.from(jsonDecode(payload) as Map));
    } catch (_) {
      _open(const {});
    }
  }

  /// Opens the screen the notification is about (or the Alerts list if it has no type).
  static void _open(Map<String, dynamic> data) {
    // Wait until the home screen is there (the app may be starting up).
    Future.delayed(const Duration(milliseconds: 600), () {
      final nav = navigatorKey.currentState;
      if (nav == null || !nav.mounted || !(_session?.signedIn ?? false)) return;
      final type = data['type'] as String?;
      if (type == null) {
        nav.push(MaterialPageRoute(builder: (_) => const AlertsScreen()));
        return;
      }
      openAlert(nav.context, {'type': type, 'title': data['title'], 'body': data['body'], 'student_id': data['student_id'], 'data': data});
    });
  }
}
