import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'push.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// SOS alarm for school staff (teacher, office, principal), whatever mode the app is in.
///
/// While any SOS from a bus is unanswered, a full-screen red alarm with a looping siren is shown.
/// As soon as anyone - on any phone or on the website - taps "I'm handling it", the alarm stops
/// everywhere (checked every 8 seconds, and at once when the "SOS answered" notification arrives).
class SosWatch with WidgetsBindingObserver {
  SosWatch._();

  static final _instance = SosWatch._();
  static final active = ValueNotifier<List<Map<String, dynamic>>>([]);
  static final _player = AudioPlayer();
  static Session? _session;
  static Timer? _timer;
  static Timer? _buzz;
  static bool _ringing = false;
  static bool _showing = false;
  static bool _observing = false;
  // SOS calls silenced on this phone; a new SOS rings again.
  static final _muted = <int>{};

  static const _roles = ['school_admin', 'transport_manager', 'office_staff', 'teacher'];

  static bool get _eligible {
    final s = _session;
    return s != null &&
        s.signedIn &&
        s.roles.any(_roles.contains) &&
        s.has('transport');
  }

  /// Start watching for the signed-in user (safe to call again after login or a profile refresh).
  static void start(Session session) {
    _session = session;
    _timer?.cancel();
    if (!_eligible) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(_instance);
      _observing = true;
    }
    check();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => check());
  }

  static void stop() {
    _timer?.cancel();
    _silence();
    active.value = const [];
  }

  /// Back in the app: look again straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  static Future<void> check() async {
    final session = _session;
    if (session == null || !_eligible) return;
    try {
      final data = await session.api.get('/sos/active') as Map<String, dynamic>;
      final list = List<Map<String, dynamic>>.from((data['sos'] as List).map((s) => Map<String, dynamic>.from(s as Map)));
      active.value = list;
      if (list.isEmpty) {
        _muted.clear();
        await _silence();
      } else {
        if (list.any((s) => !_muted.contains(s['id']))) await _ring();
        _open();
      }
    } catch (_) {
      // Offline: try again at the next check.
    }
  }

  static Future<void> _ring() async {
    if (_ringing) return;
    _ringing = true;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/siren.wav'), volume: 1);
    } catch (_) {
      // No sound possible: the red screen and vibration still show it.
    }
    _buzz?.cancel();
    _buzz = Timer.periodic(const Duration(milliseconds: 1200), (_) => HapticFeedback.vibrate());
  }

  /// "Silence this phone only": the red screen stays until someone handles it.
  static Future<void> muteHere() async {
    _muted.addAll(active.value.map((s) => s['id'] as int));
    await _silence();
  }

  static Future<void> _silence() async {
    _ringing = false;
    _buzz?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
  }

  static void _open() {
    if (_showing) return;
    final nav = Push.navigatorKey.currentState;
    if (nav == null) return;
    _showing = true;
    nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SosAlarmScreen())).whenComplete(() => _showing = false);
  }
}

class SosAlarmScreen extends StatefulWidget {
  const SosAlarmScreen({super.key});

  @override
  State<SosAlarmScreen> createState() => _SosAlarmScreenState();
}

class _SosAlarmScreenState extends State<SosAlarmScreen> {
  bool _closing = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    SosWatch.active.addListener(_onChange);
  }

  @override
  void dispose() {
    SosWatch.active.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    // Someone (anywhere) is handling it: close the alarm on this phone too.
    if (SosWatch.active.value.isEmpty && !_closing && mounted) {
      _closing = true;
      // pop() (not maybePop): this screen blocks Back while an SOS is open.
      Navigator.of(context).pop();
      toast(context, 'The SOS is being handled. Alarm stopped.');
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handle(Map<String, dynamic> sos) async {
    final result = await guard(context, () => apiOf(context).post('/sos/${sos['id']}/acknowledge'));
    if (result != null) await SosWatch.check();
  }

  @override
  Widget build(BuildContext context) {
    final list = SosWatch.active.value;

    return PopScope(
      // Not dismissible by Back while an SOS is unanswered.
      canPop: list.isEmpty,
      child: Scaffold(
        backgroundColor: const Color(0xFFB42318),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 84),
              const SizedBox(height: 8),
              const Text('SOS FROM A SCHOOL BUS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              const Text('Call the driver now. Tap "I\'m handling it" so the alarm stops for everyone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 20),
              for (final sos in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${sos['route'] ?? 'Bus'}${sos['vehicle'] != null ? '  ·  ${sos['vehicle']}' : ''}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('${sos['driver'] ?? 'The driver'} pressed SOS at ${sos['time']} (${sos['minutes']} min ago)', style: const TextStyle(color: AppColors.soft, fontSize: 15)),
                    const SizedBox(height: 14),
                    if (sos['phone'] != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size.fromHeight(54)),
                        onPressed: () => launchUrl(Uri.parse('tel:+91${sos['phone']}')),
                        icon: const Icon(Icons.call_rounded),
                        label: Text('Call driver ${sos['phone']}', style: const TextStyle(fontSize: 17)),
                      ),
                    if (sos['map'] != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(sos['map'] as String), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.place_rounded),
                        label: const Text('Open bus location'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.amber, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(54)),
                      onPressed: () => _handle(sos),
                      icon: const Icon(Icons.front_hand_rounded),
                      label: const Text("I'm handling it", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              TextButton.icon(
                onPressed: _muted
                    ? null
                    : () {
                        SosWatch.muteHere();
                        setState(() => _muted = true);
                      },
                icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
                label: Text(_muted ? 'Sound off on this phone' : 'Silence this phone only', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
