import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/common_screens.dart';
import '../core/conversation.dart';
import '../core/i18n.dart';
import '../core/offline_queue.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../parent/learning_screens.dart' show TimetableScreen;
import 'mark_attendance.dart';
import 'teacher_homework.dart';
import 'teacher_scan.dart';
import '../core/dismissal.dart';

class TeacherHome extends StatefulWidget {
  const TeacherHome({super.key});

  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  int _tab = const int.fromEnvironment('PREVIEW_TAB');

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    // Tabs of features the school has switched off are left out.
    final tabs = <(Widget, NavigationDestination)>[
      (const _ClassesTab(), const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Classes')),
      if (session.has('homework')) (const TeacherHomeworkScreen(), const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Homework')),
      if (session.has('leave')) (const TeacherLeaveScreen(), const NavigationDestination(icon: Icon(Icons.event_busy_outlined), selectedIcon: Icon(Icons.event_busy_rounded), label: 'Leave')),
      if (session.has('chat'))
        (const TeacherChatsScreen(), const NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Messages')),
      (const ProfileScreen(), const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile')),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      body: IndexedStack(index: tab, children: [for (final t in tabs) t.$1]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => _tab = i), destinations: [for (final t in tabs) t.$2]),
    );
  }
}

class _ClassesTab extends StatefulWidget {
  const _ClassesTab();

  @override
  State<_ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<_ClassesTab> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();
  bool _checkingIn = false;

  /// Classes are remembered on the phone so attendance can be taken without internet.
  Future<List<dynamic>> _load() async {
    final session = context.read<Session>();
    final queue = context.read<OfflineQueue>();
    try {
      await queue.flush();
      final data = await session.api.get('/teacher/sections') as Map<String, dynamic>;
      await session.prefs.setString('cache_sections', jsonEncode(data['sections']));
      return data['sections'] as List<dynamic>;
    } on ApiException catch (e) {
      final cached = session.prefs.getString('cache_sections');
      if (e.offline && cached != null) return jsonDecode(cached) as List<dynamic>;
      rethrow;
    }
  }

  Future<void> _checkIn() async {
    setState(() => _checkingIn = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw ApiException('Allow location permission to mark your attendance.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) throw ApiException('Turn on location (GPS) and try again.');

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      final data = await apiOf(context).post('/staff/check-in', {'latitude': position.latitude, 'longitude': position.longitude}) as Map<String, dynamic>;
      if (mounted) toast(context, 'Your attendance is marked at ${niceTime(data['check_in_time'] as String?)}.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not get your location. Please try again near a window or outside.', error: true);
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final queue = context.watch<OfflineQueue>();

    return Loader<List<dynamic>>(
      key: _loader,
      load: _load,
      builder: (context, sections, reload) {
        final done = sections.where((s) => (s as Map)['attendance_marked_today'] == true).length;

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    niceDate(DateTime.now().toIso8601String(), pattern: 'EEEE, d MMMM'),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  Text(
                    session.userName,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _HeaderStat(value: '$done / ${sections.length}', label: 'Classes marked today'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HeaderStat(value: '${sections.fold<int>(0, (sum, s) => sum + ((s as Map)['students'] as int? ?? 0))}', label: 'Students'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OfflineBanner(
                    pending: queue.pending,
                    onRetry: () async {
                      await queue.flush();
                      reload();
                    },
                  ),
                  Row(
                    children: [
                      for (final action in [
                        if (session.has('qr_attendance'))
                          _QuickAction(icon: Icons.qr_code_scanner_rounded, label: 'Scan ID card', color: AppColors.blue, onTap: () => open(context, const TeacherScanScreen())),
                        if (session.has('timetable'))
                          _QuickAction(
                            icon: Icons.grid_view_rounded,
                            label: tr('Timetable'),
                            color: const Color(0xFF7A4DFF),
                            onTap: () => open(context, const TimetableScreen(path: '/teacher/timetable')),
                          ),
                        if (session.has('dismissal'))
                          _QuickAction(icon: Icons.door_front_door_rounded, label: 'Dismissal', color: const Color(0xFF0E7C66), onTap: () => open(context, const DismissalScanScreen())),
                        if (session.has('staff_attendance'))
                          _QuickAction(icon: Icons.my_location_rounded, label: _checkingIn ? 'Checking...' : 'My check-in', color: AppColors.green, onTap: _checkingIn ? null : _checkIn),
                      ].indexed) ...[if (action.$1 > 0) const SizedBox(width: 10), Expanded(child: action.$2)],
                    ],
                  ),
                  const SectionTitle('My classes'),
                  if (sections.isEmpty)
                    const Panel(
                      child: Text('No classes are assigned to you yet. Please ask the school office.', style: TextStyle(color: AppColors.soft)),
                    ),
                  for (final s in sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Builder(
                        builder: (context) {
                          final section = Map<String, dynamic>.from(s as Map);
                          final marked = section['attendance_marked_today'] == true;
                          return Panel(
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarkAttendanceScreen(section: section)));
                              reload();
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(gradient: Brand.current.gradient, borderRadius: BorderRadius.circular(18)),
                                  child: Text(
                                    (section['name'] as String).replaceAll(' ', ''),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Class ${section['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                      Text('${section['students']} students', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Pill(marked ? 'Marked' : 'Take attendance', color: marked ? AppColors.green : AppColors.amber, icon: marked ? Icons.check_rounded : Icons.edit_calendar_rounded),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          IconBadge(icon, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Leave requests to approve. A tab in the teacher home, or opened on its own from an alert.
class TeacherLeaveScreen extends StatefulWidget {
  const TeacherLeaveScreen({super.key, this.standalone = false});

  final bool standalone;

  @override
  State<TeacherLeaveScreen> createState() => _TeacherLeaveScreenState();
}

class _TeacherLeaveScreenState extends State<TeacherLeaveScreen> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  Future<void> _decide(Map<String, dynamic> leave, bool approve) async {
    final remark = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve leave?' : 'Do not approve?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${leave['student']} - ${niceDate(leave['from_date'] as String, pattern: 'd MMM')} to ${niceDate(leave['to_date'] as String)}'),
            const SizedBox(height: 12),
            TextField(
              controller: remark,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Note to the parent (optional)', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: approve ? AppColors.green : AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await guard(context, () => apiOf(context).put('/teacher/leave/${leave['id']}', {'approve': approve, 'remark': remark.text.trim()}));
    if (done != null) {
      _loader.currentState?.reload();
      if (mounted) toast(context, approve ? 'Approved. Those days are marked "on leave".' : 'The parent has been informed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave requests'), automaticallyImplyLeading: widget.standalone),
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/teacher/leave', query: {'status': 'all'})) as Map<String, dynamic>)['leaves'] as List<dynamic>,
        builder: (context, leaves, _) {
          if (leaves.isEmpty) return const EmptyState(icon: Icons.event_available_rounded, title: 'No leave requests', subtitle: 'Requests from parents of your classes appear here.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: leaves.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final leave = Map<String, dynamic>.from(leaves[i] as Map);
              final pending = leave['status'] == 'pending';
              return Panel(
                borderColor: pending ? AppColors.amber : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${leave['student']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        Pill(
                          pending ? 'Waiting' : (leave['status'] == 'approved' ? 'Approved' : 'Not approved'),
                          color: pending ? AppColors.amber : (leave['status'] == 'approved' ? AppColors.green : AppColors.red),
                        ),
                      ],
                    ),
                    Text(
                      'Class ${leave['class']}  -  ${niceDate(leave['from_date'] as String, pattern: 'd MMM')} to ${niceDate(leave['to_date'] as String)}',
                      style: const TextStyle(color: AppColors.soft, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(leave['reason'] as String, style: const TextStyle(height: 1.4)),
                    if (pending) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _decide(leave, false),
                              child: const Text('Reject', style: TextStyle(color: AppColors.red)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size.fromHeight(52)),
                              onPressed: () => _decide(leave, true),
                              child: const Text('Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Parent conversations. A tab in the teacher home, or opened on its own from an alert.
class TeacherChatsScreen extends StatelessWidget {
  const TeacherChatsScreen({super.key, this.standalone = false});

  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages'), automaticallyImplyLeading: standalone),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/teacher/chats')) as Map<String, dynamic>)['threads'] as List<dynamic>,
        builder: (context, threads, reload) {
          if (threads.isEmpty) return const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', subtitle: 'Parents start a conversation from their app.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: threads.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final thread = Map<String, dynamic>.from(threads[i] as Map);
              final unread = thread['unread'] as int? ?? 0;
              return Panel(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationScreen(
                        title: thread['parent'] as String? ?? 'Parent',
                        subtitle: '${thread['student']} - Class ${thread['class']}',
                        path: '/teacher/chats/${thread['id']}/messages',
                      ),
                    ),
                  );
                  reload();
                },
                child: Row(
                  children: [
                    Avatar(name: thread['parent'] as String? ?? '?'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(thread['parent'] as String? ?? 'Parent', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          Text('${thread['student']} - Class ${thread['class']}', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (unread > 0)
                      Pill('$unread new', color: AppColors.red, solid: true)
                    else
                      Text(
                        niceDate(thread['last_message_at'] as String?, pattern: 'd MMM'),
                        style: const TextStyle(color: AppColors.soft, fontSize: 12),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
