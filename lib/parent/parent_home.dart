import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/common_screens.dart';
import '../core/i18n.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'attendance_screen.dart';
import 'bus_screen.dart';
import 'chat_screens.dart';
import 'fees_screen.dart';
import 'learning_screens.dart';
import 'leave_screen.dart';
import 'school_screens.dart';
import 'tests_screens.dart';
import 'pickup_screen.dart';

/// Shell of the parent app: loads the children, keeps the selected child, shows the tabs.
class ParentHome extends StatefulWidget {
  const ParentHome({super.key});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  int _tab = const int.fromEnvironment('PREVIEW_TAB');
  int _childIndex = 0;
  List<String> _tabKeys = const ['home'];
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    // The loading and "no internet" states need a page behind them.
    return Scaffold(
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/children')) as Map<String, dynamic>)['children'] as List<dynamic>,
        builder: (context, children, reload) {
          if (children.isEmpty) {
            return Scaffold(
              body: EmptyState(
                icon: Icons.family_restroom_rounded,
                title: 'No child is linked to this number',
                subtitle: 'Please ask the school office to link your child to your mobile number.',
                action: tr('Sign out'),
                onAction: () => context.read<Session>().logout(),
              ),
            );
          }

          final index = _childIndex.clamp(0, children.length - 1);
          final child = Map<String, dynamic>.from(children[index] as Map);

          final session = context.watch<Session>();
          // Tabs for switched-off features (fees, bus) are left out.
          final tabs = <(String, Widget, NavigationDestination)>[
            (
              'home',
              _HomeTab(children: children, index: index, onPick: (i) => setState(() => _childIndex = i), reload: reload, goTo: (key) => setState(() => _tab = _tabKeys.indexOf(key))),
              NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr('Home')),
            ),
            if (session.has('fees'))
              (
                'fees',
                FeesScreen(child: child, embedded: true, onChanged: reload),
                NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet_rounded), label: tr('Fees')),
              ),
            if (session.has('transport'))
              (
                'bus',
                BusScreen(child: child, embedded: true),
                NavigationDestination(icon: const Icon(Icons.directions_bus_outlined), selectedIcon: const Icon(Icons.directions_bus_rounded), label: tr('Bus')),
              ),
            (
              'alerts',
              const AlertsScreen(embedded: true),
              NavigationDestination(icon: const Icon(Icons.notifications_none_rounded), selectedIcon: const Icon(Icons.notifications_rounded), label: tr('Alerts')),
            ),
            (
              'profile',
              ProfileScreen(
                extra: [
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconBadge(Icons.privacy_tip_rounded),
                      title: Text(tr('Privacy and consent'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(child['name'] as String),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => open(context, ConsentScreen(child: child)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr('Profile')),
            ),
          ];
          _tabKeys = [for (final t in tabs) t.$1];
          final tab = _tab.clamp(0, tabs.length - 1);

          return Scaffold(
            body: IndexedStack(index: tab, children: [for (final t in tabs) t.$2]),
            bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => _tab = i), destinations: [for (final t in tabs) t.$3]),
          );
        },
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.children, required this.index, required this.onPick, required this.reload, required this.goTo});

  final List<dynamic> children;
  final int index;
  final void Function(int) onPick;
  final Future<void> Function() reload;
  final void Function(String tab) goTo;

  String get _greeting {
    final hour = DateTime.now().hour;
    return tr(hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening'));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final child = Map<String, dynamic>.from(children[index] as Map);
    final status = child['today_attendance'] as String?;
    final due = (child['fee_due'] as num?) ?? 0;

    final (statusLabel, statusColor, statusIcon) = switch (status) {
      'present' => (tr('Present'), AppColors.green, Icons.check_circle_rounded),
      'late' => (tr('Late'), AppColors.amber, Icons.schedule_rounded),
      'half_day' => (tr('Half day'), AppColors.amber, Icons.timelapse_rounded),
      'absent' => (tr('Absent'), AppColors.red, Icons.cancel_rounded),
      'leave' => (tr('On leave'), AppColors.blue, Icons.event_busy_rounded),
      _ => (tr('Not marked yet'), AppColors.soft, Icons.hourglass_empty_rounded),
    };

    // Tiles of features the school has switched off are hidden.
    final actions = <(String?, String, IconData, Color, Widget)>[
      (null, tr('Attendance'), Icons.calendar_month_rounded, AppColors.green, AttendanceScreen(child: child)),
      ('homework', tr('Homework'), Icons.menu_book_rounded, const Color(0xFF7A4DFF), HomeworkScreen(child: child)),
      ('exams', tr('Results'), Icons.emoji_events_rounded, AppColors.amber, ResultsScreen(child: child)),
      ('timetable', tr('Timetable'), Icons.grid_view_rounded, AppColors.blue, TimetableScreen(child: child)),
      ('notices', tr('Notices'), Icons.campaign_rounded, const Color(0xFFFF5C7A), NoticesScreen(child: child)),
      ('online_tests', tr('Online tests'), Icons.quiz_rounded, const Color(0xFF0AA5C2), TestsScreen(child: child)),
      ('leave', tr('Leave'), Icons.event_busy_rounded, const Color(0xFFFF8A3D), LeaveScreen(child: child)),
      ('chat', tr('Chat'), Icons.chat_bubble_rounded, const Color(0xFF12B886), ChatTeachersScreen(child: child)),
      ('dismissal', tr('Pickup'), Icons.transfer_within_a_station_rounded, const Color(0xFF0E7C66), PickupScreen(child: child)),
      ('notices', tr('Calendar'), Icons.event_rounded, const Color(0xFF1F3A8A), const CalendarScreen()),
      ('notices', tr('Gallery'), Icons.photo_library_rounded, const Color(0xFFB5179E), const GalleryScreen()),
    ].where((a) => a.$1 == null || session.has(a.$1!)).map((a) => (a.$2, a.$3, a.$4, a.$5)).toList();

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            bottom: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$_greeting,', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14)),
                          Text(
                            session.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Text(
                              session.schoolName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Child switcher
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: children.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final c = Map<String, dynamic>.from(children[i] as Map);
                      final selected = i == index;
                      return GestureDetector(
                        onTap: () => onPick(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.2)),
                          ),
                          child: Row(
                            children: [
                              Avatar(name: c['name'] as String, photoUrl: c['photo_url'] as String?, radius: 24),
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['name'] as String,
                                    style: TextStyle(color: selected ? AppColors.ink : Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                  Text('${tr('Class')} ${c['class'] ?? '-'}', style: TextStyle(color: selected ? AppColors.soft : Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Today's attendance
                Panel(
                  onTap: () => open(context, AttendanceScreen(child: child)),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: Icon(statusIcon, color: statusColor, size: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Today'),
                              style: const TextStyle(color: AppColors.soft, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              statusLabel,
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: statusColor == AppColors.soft ? AppColors.ink : statusColor),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.soft),
                    ],
                  ),
                ),
                if (session.has('fees') || session.has('transport')) const SizedBox(height: 12),
                if (session.has('fees') || session.has('transport'))
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (session.has('fees'))
                          Expanded(
                            child: Panel(
                              onTap: () => goTo('fees'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IconBadge(Icons.account_balance_wallet_rounded, color: due > 0 ? AppColors.red : AppColors.green, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    tr('Fees due'),
                                    style: const TextStyle(color: AppColors.soft, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      due > 0 ? money(due) : tr('No dues'),
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: due > 0 ? AppColors.red : AppColors.green),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (session.has('fees') && session.has('transport')) const SizedBox(width: 12),
                        if (session.has('transport'))
                          Expanded(
                            child: Panel(
                              onTap: () => goTo('bus'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const IconBadge(Icons.directions_bus_rounded, color: AppColors.amber, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    tr('School bus'),
                                    style: const TextStyle(color: AppColors.soft, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    (child['bus_stop'] as String?) ?? 'Not using bus',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                SectionTitle(tr('Everything in one place')),
                GridView.count(
                  crossAxisCount: 4,
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.92,
                  children: [
                    for (final (label, icon, color, page) in actions)
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => open(context, page),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.white, 0.28)!]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 8))],
                              ),
                              child: Icon(icon, color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
