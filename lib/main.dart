import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'core/config.dart';
import 'core/i18n.dart';
import 'core/offline_queue.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'core/sos_alarm.dart';
import 'core/theme.dart';
import 'driver/driver_home.dart';
import 'gate/gate_screen.dart';
import 'parent/parent_home.dart';
import 'teacher/teacher_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final session = Session();
  await session.load();
  final queue = OfflineQueue(session.api);
  await queue.load();
  // Anything saved without internet is retried every 30 seconds until it goes through.
  Timer.periodic(const Duration(seconds: 30), (_) => queue.flush());
  if (session.signedIn) {
    unawaited(Push.start(session));
    unawaited(session.refresh());
    SosWatch.start(session);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: queue),
      ],
      child: const SchoolSathiApp(),
    ),
  );
}

class SchoolSathiApp extends StatelessWidget {
  const SchoolSathiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    return MaterialApp(
      navigatorKey: Push.navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Rebuild everything when the language or the signed-in user changes.
      home: KeyedSubtree(
        key: ValueKey('${I18n.locale}-${session.signedIn}-${session.user?['id']}-${AppConfig.kind.name}'),
        child: !session.signedIn
            ? const LoginScreen()
            : session.mustChangePassword
            ? const ChangePasswordScreen(firstTime: true)
            : _home(),
      ),
    );
  }

  Widget _home() => switch (AppConfig.kind) {
    AppKind.parent => const ParentHome(),
    AppKind.teacher => const TeacherHome(),
    AppKind.driver => const DriverHome(),
    AppKind.gate => const GateScreen(),
  };
}
