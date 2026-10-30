import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/common_screens.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/i18n.dart';
import '../core/widgets.dart';
import 'trip_screen.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();
  bool _starting = false;

  Future<void> _openTrip(Map<String, dynamic> route, int tripId, String direction) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripScreen(route: route, tripId: tripId, direction: direction),
      ),
    );
    _loader.currentState?.reload();
  }

  Future<void> _start(Map<String, dynamic> route, String direction) async {
    setState(() => _starting = true);
    final data = await guard(context, () => apiOf(context).post('/driver/routes/${route['id']}/trips', {'direction': direction}));
    if (mounted) setState(() => _starting = false);
    if (data != null && mounted) await _openTrip(route, (data as Map)['trip_id'] as int, direction);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final api = session.api;

    if (!session.has('transport')) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.directions_bus_rounded,
          title: 'Bus tracking is not switched on for your school',
          subtitle: 'Please contact the school office.',
          action: tr('Sign out'),
          onAction: session.logout,
        ),
      );
    }

    return Scaffold(
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/driver/routes')) as Map<String, dynamic>)['routes'] as List<dynamic>,
        builder: (context, routes, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          niceDate(DateTime.now().toIso8601String(), pattern: 'EEEE, d MMMM'),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        Text(
                          session.userName,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        Text(session.schoolName, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18), minimumSize: const Size(52, 52)),
                    onPressed: () => open(context, const ProfileScreen(embedded: false)),
                    icon: const Icon(Icons.person_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (routes.isEmpty)
                    const Panel(
                      child: Text('No bus route is assigned to you yet. Please ask the school office.', style: TextStyle(color: AppColors.soft, fontSize: 16)),
                    ),
                  for (final r in routes)
                    Builder(
                      builder: (context) {
                        final route = Map<String, dynamic>.from(r as Map);
                        final active = route['active_trip'] == null ? null : Map<String, dynamic>.from(route['active_trip'] as Map);
                        final stops = route['stops'] as List;
                        final students = stops.fold<int>(0, (sum, s) => sum + ((s as Map)['students'] as int? ?? 0));

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Panel(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const IconBadge(Icons.directions_bus_rounded, size: 52),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(route['name'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                          Text('${route['vehicle'] ?? 'No vehicle'}  -  ${stops.length} stops  -  $students children', style: const TextStyle(color: AppColors.soft)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                if (active != null)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size.fromHeight(64)),
                                    onPressed: () => _openTrip(route, active['id'] as int, active['direction'] as String),
                                    icon: const Icon(Icons.play_circle_fill_rounded, size: 28),
                                    label: const Text('Continue trip', style: TextStyle(fontSize: 18)),
                                  )
                                else ...[
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                                    onPressed: _starting ? null : () => _start(route, 'pickup'),
                                    icon: const Icon(Icons.wb_sunny_rounded, size: 26),
                                    label: const Text('Start morning pickup', style: TextStyle(fontSize: 18)),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                                    onPressed: _starting ? null : () => _start(route, 'drop'),
                                    icon: const Icon(Icons.home_rounded, size: 26),
                                    label: const Text('Start afternoon drop', style: TextStyle(fontSize: 18)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
