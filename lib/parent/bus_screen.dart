import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Live bus for one child. Refreshes every 10 seconds while the screen is open.
class BusScreen extends StatefulWidget {
  const BusScreen({super.key, required this.child, this.embedded = false});

  final Map<String, dynamic> child;
  final bool embedded;

  @override
  State<BusScreen> createState() => _BusScreenState();
}

class _BusScreenState extends State<BusScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;
  final _map = MapController();
  bool _centred = false;

  int get _childId => widget.child['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void didUpdateWidget(BusScreen old) {
    super.didUpdateWidget(old);
    if (old.child['id'] != widget.child['id']) {
      _data = null;
      _centred = false;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await apiOf(context).get('/children/$_childId/bus') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = '$e');
    }
  }

  Future<void> _toggleAbsence(bool notComing) async {
    final ok = await guard(context, () => apiOf(context).put('/children/$_childId/bus/absence', {
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'direction': notComing ? 'both' : 'none',
        }));
    if (ok != null) {
      await _load();
      if (mounted) toast(context, notComing ? 'Noted. The driver will not wait for your child today.' : 'Your child is expected on the bus again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = tr('School bus');
    Widget body;

    if (_data == null) {
      body = _error != null
          ? EmptyState(icon: Icons.cloud_off_rounded, title: _error!, action: tr('Retry'), onAction: _load)
          : const Center(child: CircularProgressIndicator());
    } else if (_data!['assigned'] != true) {
      body = const EmptyState(icon: Icons.directions_walk_rounded, title: 'Not using the school bus', subtitle: 'Ask the school office to add your child to a bus route.');
    } else {
      body = _content(_data!);
    }

    if (widget.embedded) return Scaffold(appBar: AppBar(title: Text(title), automaticallyImplyLeading: false), body: body);
    return AppPage(title: title, body: body);
  }

  Widget _content(Map<String, dynamic> data) {
    final route = Map<String, dynamic>.from(data['route'] as Map);
    final stop = Map<String, dynamic>.from(data['stop'] as Map);
    final trip = data['trip'] == null ? null : Map<String, dynamic>.from(data['trip'] as Map);
    final notComing = data['not_taking_bus_today'] != null;

    final stopPoint = stop['latitude'] == null ? null : LatLng((stop['latitude'] as num).toDouble(), (stop['longitude'] as num).toDouble());
    final busPoint = trip?['latitude'] == null ? null : LatLng((trip!['latitude'] as num).toDouble(), (trip['longitude'] as num).toDouble());

    if (busPoint != null && !_centred) {
      _centred = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(busPoint, 15);
        } catch (_) {
          // The map is not on screen yet.
        }
      });
    }

    final eta = trip?['eta_minutes'] as int?;
    final reached = trip?['stop_reached'] == true;
    final boarded = trip?['boarded_at'] != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: busPoint ?? stopPoint ?? const LatLng(19.2, 72.97), initialZoom: busPoint != null || stopPoint != null ? 14.5 : 10),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.schoolsathi.app'),
                    MarkerLayer(markers: [
                      if (stopPoint != null)
                        Marker(point: stopPoint, width: 44, height: 44, child: const _MapPin(icon: Icons.home_rounded, color: AppColors.blue)),
                      if (busPoint != null)
                        Marker(point: busPoint, width: 54, height: 54, child: const _MapPin(icon: Icons.directions_bus_rounded, color: AppColors.amber, big: true)),
                    ]),
                  ],
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Pill(trip == null ? tr('No trip is running now') : tr('Bus is on the way'), color: trip == null ? AppColors.soft : AppColors.green, solid: true, icon: trip == null ? Icons.pause_circle_outline_rounded : Icons.sensors_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (trip != null)
          Panel(
            gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF5C7A)]),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        boarded ? '${widget.child['name']} is on the bus' : (reached ? 'Bus is at ${stop['name']}' : (eta == null ? 'Waiting for the bus location' : (eta <= 1 ? 'Arriving now' : 'About $eta min away'))),
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      Text('${trip['direction'] == 'pickup' ? 'Morning pickup' : 'Afternoon drop'} - ${route['name']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (trip != null) const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              _row(Icons.signpost_rounded, 'Stop', '${stop['name']}${stop['pickup_time'] != null ? '  -  pickup ${niceTime(stop['pickup_time'] as String?)}' : ''}'),
              const Divider(height: 22),
              _row(Icons.alt_route_rounded, 'Route', '${route['name']}${route['vehicle'] != null ? '  -  ${route['vehicle']}' : ''}'),
              if (route['driver'] != null) ...[
                const Divider(height: 22),
                _row(Icons.badge_rounded, 'Driver', '${route['driver']}${route['driver_phone'] != null ? '  -  ${route['driver_phone']}' : ''}'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: notComing,
            onChanged: _toggleAbsence,
            title: Text(tr('Not taking the bus today'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('The driver sees this and will not wait'),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        IconBadge(icon, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.soft, fontSize: 12, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.icon, required this.color, this.big = false});

  final IconData icon;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]),
      child: Icon(icon, color: Colors.white, size: big ? 28 : 22),
    );
  }
}
