import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/common_screens.dart';
import '../core/offline_queue.dart';
import '../core/scanner.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/i18n.dart';
import '../core/widgets.dart';
import '../core/dismissal.dart';

/// Gate device: one screen that keeps scanning ID cards and shows a big green or red result.
class GateScreen extends StatefulWidget {
  const GateScreen({super.key});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  bool _busy = false;
  bool? _ok;
  String _headline = 'Ready to scan';
  String _detail = 'Show the QR code on the ID card to the camera';
  int _count = 0;
  // Dismissal mode: a scan opens the check-out screen instead of marking arrival.
  bool _dismissal = false;
  Timer? _reset;
  Timer? _sync;

  @override
  void initState() {
    super.initState();
    // Send scans that were saved while the internet was down.
    _sync = Timer.periodic(const Duration(seconds: 30), (_) => context.read<OfflineQueue>().flush());
  }

  @override
  void dispose() {
    _reset?.cancel();
    _sync?.cancel();
    super.dispose();
  }

  void _show(bool ok, String headline, String detail) {
    setState(() {
      _ok = ok;
      _headline = headline;
      _detail = detail;
      _busy = false;
    });
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _ok = null;
          _headline = 'Ready to scan';
          _detail = 'Show the QR code on the ID card to the camera';
        });
      }
    });
  }

  void _showStudent(Map<String, dynamic> data) {
    final student = Map<String, dynamic>.from(data['student'] as Map);
    final already = data['already_marked'] == true;
    if (!already) _count++;
    _show(true, student['name'] as String, already ? 'Class ${student['class']} - already marked today' : 'Class ${student['class']} - present at ${niceTime(data['check_in_time'] as String?)}');
  }

  Future<void> _onCode(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_dismissal) {
      final data = await guard(context, () => apiOf(context).post('/teacher/dismissal/lookup', {'code': code}));
      if (data != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DismissalCheckScreen(data: Map<String, dynamic>.from(data as Map))));
      }
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final data = await context.read<OfflineQueue>().postOrQueue('/teacher/attendance/scan', {'code': code});
      if (data == null) {
        _count++;
        _show(true, 'Saved', 'No internet. Attendance will be sent automatically.');
      } else {
        _showStudent(Map<String, dynamic>.from(data as Map));
      }
    } on ApiException catch (e) {
      _show(false, 'Not recognised', e.message);
    }
  }

  /// For students enrolled for face recognition: take one photo of the face.
  Future<void> _faceScan() async {
    if (_busy) return;
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, imageQuality: 75, maxWidth: 1200);
      if (photo == null || !mounted) return;
      setState(() => _busy = true);
      final data = await apiOf(context).upload('/teacher/attendance/face', files: [UploadFile('photo', 'face.jpg', await photo.readAsBytes())]);
      _showStudent(Map<String, dynamic>.from(data as Map));
    } on ApiException catch (e) {
      _show(false, 'Face not recognised', e.message);
    } catch (_) {
      _show(false, 'Camera problem', 'Could not take the photo. Please scan the ID card.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final queue = context.watch<OfflineQueue>();
    final color = _ok == null ? AppColors.ink : (_ok! ? AppColors.green : AppColors.red);

    if (!session.has('qr_attendance') && !session.has('face_attendance')) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Gate scanning is not switched on for your school',
          subtitle: 'Please contact the school office.',
          action: tr('Sign out'),
          onAction: session.logout,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.schoolName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${niceDate(DateTime.now().toIso8601String(), pattern: 'EEE, d MMM')}  -  $_count marked${queue.pending > 0 ? '  -  ${queue.pending} waiting for internet' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (session.has('dismissal')) ...[
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: Colors.black,
                        selectedBackgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Arrival')),
                        ButtonSegment(value: true, label: Text('Leaving')),
                      ],
                      selected: {_dismissal},
                      onSelectionChanged: (v) => setState(() => _dismissal = v.first),
                    ),
                    if (_dismissal)
                      IconButton(
                        onPressed: () => open(context, const StillInSchoolScreen()),
                        tooltip: 'Still in school',
                        icon: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
                      ),
                  ],
                  if (session.has('face_attendance') && !_dismissal)
                    IconButton(
                      onPressed: _faceScan,
                      tooltip: 'Face scan',
                      icon: const Icon(Icons.face_retouching_natural_rounded, color: Colors.white, size: 28),
                    ),
                  IconButton(
                    onPressed: () => open(context, const ProfileScreen(embedded: false)),
                    icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: QrScannerView(onCode: _onCode, paused: _busy),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              color: color,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
              child: Row(
                children: [
                  _busy
                      ? const SizedBox(
                          width: 64,
                          height: 64,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        )
                      : Icon(_ok == null ? Icons.qr_code_scanner_rounded : (_ok! ? Icons.check_circle_rounded : Icons.cancel_rounded), color: Colors.white, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dismissal && _ok == null ? 'Leaving school' : _headline,
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(_dismissal && _ok == null ? 'Scan the ID card to see who may take the child home' : _detail, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
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
