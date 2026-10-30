import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../parent/attendance_screen.dart';
import '../parent/bus_screen.dart';
import '../parent/chat_screens.dart';
import '../parent/fees_screen.dart';
import '../parent/leave_screen.dart';
import '../parent/learning_screens.dart';
import '../parent/pickup_screen.dart';
import '../parent/tests_screens.dart';
import '../teacher/teacher_home.dart' show TeacherChatsScreen, TeacherLeaveScreen;
import 'api.dart';
import 'config.dart';
import 'conversation.dart';
import 'dismissal.dart';
import 'session.dart';
import 'sos_alarm.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the screen an alert is about: absent -> attendance, fee -> fees, bus -> live bus,
/// chat -> that conversation, SOS -> call the driver / "I'm handling it" ...
/// Used when an alert is tapped in the Alerts list and when a push notification is tapped.
///
/// [alert] = {type, title?, body?, student_id?, data?}. Push notifications carry the same keys as strings.
Future<void> openAlert(BuildContext context, Map<String, dynamic> alert) async {
  final type = alert['type'] as String? ?? '';
  final data = alert['data'] is Map ? Map<String, dynamic>.from(alert['data'] as Map) : <String, dynamic>{};
  final studentId = int.tryParse('${alert['student_id'] ?? data['student_id'] ?? ''}');

  Widget? page;

  // SOS and bus incidents are for staff, whatever mode the app is in now.
  final staff = context.read<Session>().modes.contains(AppKind.teacher);
  if (staff && (type == 'bus.sos' || type == 'bus.sos_escalated')) {
    // Still unanswered: the full-screen alarm opens. Already handled: details with Call / Location.
    await SosWatch.check();
    final open = SosWatch.active.value.any((s) => '${s['id']}' == '${data['incident_id']}');
    if (open || !context.mounted) return;
    return _sosSheet(context, alert, data, canAcknowledge: false);
  }
  if (staff && (type == 'bus.sos_handled' || type == 'bus.overspeed' || type == 'bus.empty_check_skipped')) {
    return _sosSheet(context, alert, data, canAcknowledge: false);
  }

  if (AppConfig.kind == AppKind.parent) {
    final child = await _child(context, studentId);
    if (!context.mounted) return;
    if (child != null) {
      final childId = child['id'];
      page = switch (type.split('.').first) {
        'attendance' => AttendanceScreen(child: child),
        'fee' => FeesScreen(child: child),
        'bus' => BusScreen(child: child),
        'homework' => HomeworkScreen(child: child),
        'notice' => NoticesScreen(child: child),
        'leave' => LeaveScreen(child: child),
        'exam' => ResultsScreen(child: child),
        'test' => TestsScreen(child: child),
        'dismissal' => PickupScreen(child: child),
        'chat' =>
          data['teacher_user_id'] != null
              ? ConversationScreen(title: '${data['sender'] ?? 'Teacher'}', subtitle: 'About ${child['name']}', path: '/children/$childId/chat/${data['teacher_user_id']}/messages')
              : ChatTeachersScreen(child: child),
        _ => null,
      };
    }
  } else if (AppConfig.kind == AppKind.teacher || AppConfig.kind == AppKind.gate) {
    if (type == 'attendance.low') {
      // A teacher's class: back to My classes.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (type == 'dismissal.pass_requested') {
      return _detailSheet(context, alert, data, webPath: '/dismissal?tab=passes', webLabel: 'Approve on the website');
    }
    page = switch (type) {
      'leave.requested' => const TeacherLeaveScreen(standalone: true),
      'chat.message' =>
        data['thread_id'] != null ? ConversationScreen(title: '${data['sender'] ?? 'Parent'}', path: '/teacher/chats/${data['thread_id']}/messages') : const TeacherChatsScreen(standalone: true),
      'dismissal.refused_staff' || 'dismissal.missed_bus_home_staff' => const StillInSchoolScreen(),
      _ => null,
    };
  }

  if (!context.mounted) return;
  if (page != null) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  } else {
    await _detailSheet(context, alert, data);
  }
}

/// The child an alert is about (parents with more than one child).
Future<Map<String, dynamic>?> _child(BuildContext context, int? studentId) async {
  try {
    final list = ((await apiOf(context).get('/children')) as Map<String, dynamic>)['children'] as List;
    final children = list.map((c) => Map<String, dynamic>.from(c as Map)).toList();
    if (children.isEmpty) return null;
    return children.firstWhere((c) => c['id'] == studentId, orElse: () => children.first);
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
    return null;
  }
}

Future<void> _call(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri.parse('tel:+91$phone'));
  if (!ok && context.mounted) toast(context, 'Could not start the call. Number: $phone', error: true);
}

Future<void> _sosSheet(BuildContext context, Map<String, dynamic> alert, Map<String, dynamic> data, {bool canAcknowledge = true}) async {
  final phone = data['phone'] as String?;
  final lat = data['lat'], lng = data['lng'];
  final incidentId = data['incident_id'];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sos_rounded, color: AppColors.red, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    alert['title'] as String? ?? 'SOS from bus',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert['body'] as String? ?? '', style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            if (phone != null && phone.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: () => _call(sheet, phone),
                icon: const Icon(Icons.call_rounded),
                label: Text('Call driver $phone'),
              ),
            if (lat != null && lng != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps?q=$lat,$lng'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.place_rounded),
                label: const Text('Open bus location'),
              ),
            ],
            if (incidentId != null && canAcknowledge) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8A5A00),
                  side: const BorderSide(color: AppColors.amber),
                ),
                onPressed: () async {
                  final result = await guard(sheet, () => apiOf(sheet).post('/sos/$incidentId/acknowledge'));
                  if (result != null && sheet.mounted) {
                    Navigator.of(sheet).pop();
                    toast(context, (result as Map)['message'] as String);
                  }
                },
                icon: const Icon(Icons.front_hand_rounded),
                label: const Text("I'm handling it"),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> _detailSheet(BuildContext context, Map<String, dynamic> alert, Map<String, dynamic> data, {String? webPath, String? webLabel}) async {
  final phone = data['phone'] as String?;
  final server = context.read<Session>().serverUrl;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(alert['title'] as String? ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(alert['body'] as String? ?? '', style: const TextStyle(fontSize: 15, height: 1.4)),
            if (alert['created_at'] != null) ...[
              const SizedBox(height: 8),
              Text(
                niceDate(alert['created_at'] as String?, pattern: 'd MMM, h:mm a'),
                style: const TextStyle(color: AppColors.soft),
              ),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: () => _call(sheet, phone), icon: const Icon(Icons.call_rounded), label: Text('Call $phone')),
            ],
            if (webPath != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse('$server$webPath'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: Text(webLabel ?? 'Open on the website'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
