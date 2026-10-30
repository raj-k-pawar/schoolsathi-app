import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/scanner.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Scan a student's ID card to mark them present.
class TeacherScanScreen extends StatefulWidget {
  const TeacherScanScreen({super.key});

  @override
  State<TeacherScanScreen> createState() => _TeacherScanScreenState();
}

class _TeacherScanScreenState extends State<TeacherScanScreen> {
  bool _busy = false;
  String? _name;
  String? _detail;
  bool _ok = true;
  int _count = 0;

  Future<void> _onCode(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await apiOf(context).post('/teacher/attendance/scan', {'code': code}) as Map<String, dynamic>;
      final student = Map<String, dynamic>.from(data['student'] as Map);
      setState(() {
        _ok = true;
        _name = student['name'] as String;
        _detail = data['already_marked'] == true ? 'Already marked present today' : 'Class ${student['class']} - marked present';
        if (data['already_marked'] != true) _count++;
      });
    } on ApiException catch (e) {
      setState(() {
        _ok = false;
        _name = 'Not recognised';
        _detail = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _ok ? AppColors.green : AppColors.red;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Scan ID card', style: TextStyle(color: Colors.white)), actions: [
        Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: Pill('$_count marked', color: AppColors.green, solid: true))),
      ]),
      body: Column(
        children: [
          Expanded(child: QrScannerView(onCode: _onCode, paused: _busy)),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            color: _name == null ? AppColors.ink : color,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Icon(_name == null ? Icons.qr_code_2_rounded : (_ok ? Icons.check_circle_rounded : Icons.cancel_rounded), color: Colors.white, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name ?? 'Point the camera at the QR code', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    Text(_detail ?? 'on the student\'s ID card', style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
