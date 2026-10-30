import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/offline_queue.dart';
import '../core/scanner.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// A running trip: shares the bus location, shows who should be on the bus,
/// scans children on and off, and ends with the empty-bus check.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.route, required this.tripId, required this.direction});

  final Map<String, dynamic> route;
  final int tripId;
  final String direction;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  StreamSubscription<Position>? _positions;
  Timer? _rosterTimer;
  Position? _last;
  DateTime? _lastSent;
  String _gps = 'Starting GPS...';
  bool _gpsOk = false;
  List<dynamic> _stops = [];
  bool _loaded = false;
  bool _ending = false;
  // After SOS: who at school is handling it (checked every 10 seconds until someone is).
  Map<String, dynamic>? _sosStatus;
  Timer? _sosTimer;

  String get _base => '/driver/trips/${widget.tripId}';

  @override
  void initState() {
    super.initState();
    _startLocation();
    _loadRoster();
    _rosterTimer = Timer.periodic(const Duration(seconds: 25), (_) => _loadRoster());
  }

  @override
  void dispose() {
    _positions?.cancel();
    _rosterTimer?.cancel();
    _sosTimer?.cancel();
    super.dispose();
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gps = 'GPS is off. Turn on location.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Google Play: say clearly why location is needed before Android asks.
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.location_on_rounded, size: 40),
            title: const Text('Share the bus location'),
            content: const Text(
                'During a trip, SchoolSathi uses this phone\'s location - also when the screen is off or the app is closed - to show the bus to parents and send "bus is near" alerts. Location is used only while a trip is running and stops when you end the trip.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
            ],
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _gps = 'Location permission is needed to share the bus position.');
          return;
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _gps = 'Location permission is needed to share the bus position.');
        return;
      }

      // On Android a notification keeps location running while the screen is off.
      final LocationSettings settings = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 8),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'School bus trip is running',
                notificationText: 'Sharing the bus location with the school and parents.',
                enableWakeLock: true,
                setOngoing: true,
              ),
            )
          : !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
              // iPhone: keep updating while the phone is locked; the blue bar shows location is in use.
              ? AppleSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 10,
                  activityType: ActivityType.automotiveNavigation,
                  pauseLocationUpdatesAutomatically: false,
                  allowBackgroundLocationUpdates: true,
                  showBackgroundLocationIndicator: true,
                )
              : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);

      _positions = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPosition,
        onError: (_) {
          if (mounted) {
            setState(() {
              _gps = 'GPS signal lost. Trying again...';
              _gpsOk = false;
            });
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _gps = 'Could not start GPS on this phone.');
    }
  }

  Future<void> _onPosition(Position position) async {
    _last = position;
    // At most one ping every 6 seconds, as the BRD asks for updates every 5 to 10 seconds.
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < const Duration(seconds: 6)) return;
    _lastSent = now;

    final queue = context.read<OfflineQueue>();
    try {
      final sent = await queue.sendOrQueue('$_base/location', {
        'points': [
          {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'speed': position.speed < 0 ? 0 : double.parse((position.speed * 3.6).toStringAsFixed(1)),
            'recorded_at': now.toUtc().toIso8601String(),
          },
        ],
      });
      if (sent) queue.flush();
      if (mounted) {
        setState(() {
          _gps = sent ? 'Sharing location' : 'No internet - saving location';
          _gpsOk = sent;
        });
      }
    } on ApiException catch (e) {
      // The trip was ended from somewhere else.
      if (mounted) {
        setState(() {
          _gps = e.message;
          _gpsOk = false;
        });
      }
    }
  }

  Future<void> _loadRoster() async {
    try {
      final data = await apiOf(context).get('$_base/roster') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _stops = data['stops'] as List;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Map<String, dynamic> _scanBody({String? code, int? studentId, String? event}) => {
    'scans': [
      {
        if (code != null) 'code': code,
        if (studentId != null) 'student_id': studentId,
        if (event != null) 'event': event,
        'scanned_at': DateTime.now().toUtc().toIso8601String(),
        if (_last != null) 'latitude': _last!.latitude,
        if (_last != null) 'longitude': _last!.longitude,
      },
    ],
  };

  /// Returns (ok, headline, detail) for the scan result banner.
  Future<(bool, String, String)> _scan({String? code, int? studentId, String? event}) async {
    final queue = context.read<OfflineQueue>();
    try {
      final data = await queue.postOrQueue('$_base/scan', _scanBody(code: code, studentId: studentId, event: event));
      if (data == null) return (true, 'Saved on this phone', 'No internet. It will be sent automatically.');
      final result = Map<String, dynamic>.from(((data as Map)['results'] as List).first as Map);
      _loadRoster();
      if (result['ok'] != true) return (false, (result['name'] as String?) ?? 'Not recognised', (result['message'] as String?) ?? '');
      final boarded = result['event'] == 'boarded';
      return (true, result['name'] as String, result['already'] == true ? 'Already scanned' : (boarded ? 'Boarded the bus' : 'Got off the bus'));
    } on ApiException catch (e) {
      return (false, 'Could not save', e.message);
    }
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BoardingScanner(scan: (code) => _scan(code: code)),
      ),
    );
    _loadRoster();
  }

  Future<void> _tapStudent(Map<String, dynamic> student) async {
    final boarded = student['boarded_at'] != null;
    final dropped = student['dropped_at'] != null;
    if (boarded && dropped) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(student['name'] as String),
        content: Text(boarded ? 'Mark as got off the bus?' : 'Mark as boarded the bus?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(boarded ? 'Got off' : 'Boarded'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final (success, name, detail) = await _scan(studentId: student['id'] as int, event: boarded ? 'dropped' : 'boarded');
    if (mounted) toast(context, '$name - $detail', error: !success);
  }

  Future<void> _sos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: AppColors.red, size: 44),
        title: const Text('Send SOS to the school?'),
        content: const Text('The school office is alerted at once with the bus location. Use this only in an emergency.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await guard(context, () => apiOf(context).post('$_base/sos', {if (_last != null) 'latitude': _last!.latitude, if (_last != null) 'longitude': _last!.longitude}));
    if (done != null && mounted) {
      toast(context, 'SOS sent. The school office has been alerted.');
      setState(() => _sosStatus = {'sent_at': null, 'handled_by': null});
      _sosTimer?.cancel();
      _sosTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkSos());
      _checkSos();
    }
  }

  Future<void> _checkSos() async {
    try {
      final data = await apiOf(context).get('$_base/sos') as Map<String, dynamic>;
      final sos = data['sos'] == null ? null : Map<String, dynamic>.from(data['sos'] as Map);
      if (!mounted || sos == null) return;
      setState(() => _sosStatus = sos);
      if (sos['handled_by'] != null || sos['resolved'] == true) _sosTimer?.cancel();
    } catch (_) {
      // Offline: try again in 10 seconds.
    }
  }

  Widget _sosBanner() {
    final handler = _sosStatus?['handled_by'] as String?;
    final color = handler == null ? AppColors.red : AppColors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(handler == null ? Icons.sos_rounded : Icons.support_agent_rounded, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              handler == null
                  ? 'SOS sent. Waiting for the school to answer...'
                  : 'Help is coming: $handler is handling it.${_sosStatus?['handled_at'] != null ? ' (${_sosStatus!['handled_at']})' : ''}',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          if (handler == null) SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)),
        ],
      ),
    );
  }

  Future<void> _endTrip() async {
    var checked = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('End this trip?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Before you end the trip, walk to the back of the bus and check every seat.'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                onChanged: (value) => setDialog(() => checked = value ?? false),
                title: const Text('I checked. No child is in the bus.', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (!checked) const Text('If you end without this check, the school office is alerted.', style: TextStyle(color: AppColors.red, fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: checked ? AppColors.green : AppColors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End trip'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _ending = true);
    final queue = context.read<OfflineQueue>();
    await queue.flush();
    if (!mounted) return;
    final done = await guard(context, () => apiOf(context).post('$_base/end', {'empty_bus_checked': checked}));
    if (!mounted) return;
    setState(() => _ending = false);
    if (done != null) {
      await _positions?.cancel();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<OfflineQueue>();
    final pickup = widget.direction == 'pickup';
    var total = 0;
    var boarded = 0;
    for (final stop in _stops) {
      for (final s in (stop as Map)['students'] as List) {
        total++;
        if ((s as Map)['boarded_at'] != null) boarded++;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) toast(context, 'The trip is still running. Press "End trip" when you finish.');
      },
      child: Scaffold(
        body: Column(
          children: [
            GradientHeader(
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pickup ? 'Morning pickup' : 'Afternoon drop', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                            Text(
                              widget.route['name'] as String,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onLongPress: _sos,
                        onTap: () => toast(context, 'Press and hold the SOS button in an emergency.'),
                        child: Container(
                          width: 66,
                          height: 66,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: AppColors.red.withValues(alpha: 0.6), blurRadius: 16)],
                          ),
                          child: const Text(
                            'SOS',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Pill(_gps, color: _gpsOk ? const Color(0xFF7FE8C9) : Colors.white, icon: _gpsOk ? Icons.sensors_rounded : Icons.gps_not_fixed_rounded),
                      const Spacer(),
                      Text(
                        '$boarded / $total on board',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadRoster,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        children: [
                          if (_sosStatus != null) _sosBanner(),
                          OfflineBanner(pending: queue.pending, onRetry: queue.flush),
                          if (_stops.isEmpty)
                            const Panel(
                              child: Text('The list of children will appear when internet is available. You can still scan ID cards.', style: TextStyle(color: AppColors.soft)),
                            ),
                          for (final st in _stops)
                            Builder(
                              builder: (context) {
                                final stop = Map<String, dynamic>.from(st as Map);
                                final students = stop['students'] as List;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Panel(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(color: Brand.current.primary, shape: BoxShape.circle),
                                              child: Text(
                                                '${stop['sequence']}',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(stop['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                            ),
                                            Text(
                                              '${students.length}',
                                              style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        ),
                                        for (final s in students)
                                          Builder(
                                            builder: (context) {
                                              final student = Map<String, dynamic>.from(s as Map);
                                              final on = student['boarded_at'] != null;
                                              final off = student['dropped_at'] != null;
                                              final skip = student['not_coming_today'] == true;
                                              return InkWell(
                                                onTap: skip ? null : () => _tapStudent(student),
                                                child: Padding(
                                                  padding: const EdgeInsets.only(top: 12),
                                                  child: Row(
                                                    children: [
                                                      Avatar(name: student['name'] as String, photoUrl: student['photo_url'] as String?, radius: 20),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Text(
                                                          student['name'] as String,
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w700,
                                                            decoration: skip ? TextDecoration.lineThrough : null,
                                                            color: skip ? AppColors.soft : AppColors.ink,
                                                          ),
                                                        ),
                                                      ),
                                                      if (skip)
                                                        const Pill('Not coming', color: AppColors.soft)
                                                      else if (off)
                                                        const Pill('Got off', color: AppColors.blue, icon: Icons.logout_rounded)
                                                      else if (on)
                                                        const Pill('On board', color: AppColors.green, icon: Icons.check_rounded)
                                                      else
                                                        const Pill('Waiting', color: AppColors.amber),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                        onPressed: _openScanner,
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
                        label: const Text('Scan child', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(64),
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                        ),
                        onPressed: _ending ? null : _endTrip,
                        child: _ending ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('End trip', style: TextStyle(fontSize: 17)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardingScanner extends StatefulWidget {
  const _BoardingScanner({required this.scan});

  final Future<(bool, String, String)> Function(String code) scan;

  @override
  State<_BoardingScanner> createState() => _BoardingScannerState();
}

class _BoardingScannerState extends State<_BoardingScanner> {
  bool _busy = false;
  (bool, String, String)? _result;

  Future<void> _onCode(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await widget.scan(code);
    if (mounted) {
      setState(() {
        _result = result;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ok = _result?.$1 ?? true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan ID card', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: QrScannerView(onCode: _onCode, paused: _busy),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            color: _result == null ? AppColors.ink : (ok ? AppColors.green : AppColors.red),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Icon(_result == null ? Icons.qr_code_2_rounded : (ok ? Icons.check_circle_rounded : Icons.cancel_rounded), color: Colors.white, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result?.$2 ?? 'Scan the child\'s ID card',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        Text(_result?.$3 ?? 'First scan = boarded, second scan = got off', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
