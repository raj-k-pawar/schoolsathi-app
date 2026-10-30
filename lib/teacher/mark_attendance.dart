import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/offline_queue.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Everyone is present by default: the teacher taps only the students who are absent.
class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({super.key, required this.section});

  final Map<String, dynamic> section;

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  List<Map<String, dynamic>>? _students;
  final Map<int, String> _status = {};
  String? _error;
  bool _saving = false;
  bool _fromCache = false;
  bool _alreadyMarked = false;

  static const _order = ['present', 'absent', 'late', 'leave'];
  static const _labels = {
    'present': 'Present',
    'absent': 'Absent',
    'late': 'Late',
    'half_day': 'Half day',
    'leave': 'Leave',
  };
  static const _colors = {
    'present': AppColors.green,
    'absent': AppColors.red,
    'late': AppColors.amber,
    'half_day': AppColors.amber,
    'leave': AppColors.blue,
  };

  int get _sectionId => widget.section['id'] as int;
  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    final cacheKey = 'cache_students_$_sectionId';
    List<dynamic> list;

    try {
      final data = await session.api.get(
        '/teacher/sections/$_sectionId/students',
      ) as Map<String, dynamic>;
      list = data['students'] as List;
      await session.prefs.setString(cacheKey, jsonEncode(list));
      _fromCache = false;
    } on ApiException catch (e) {
      final cached = session.prefs.getString(cacheKey);
      if (!e.offline || cached == null) {
        if (mounted) setState(() => _error = e.message);
        return;
      }
      // No internet: use the class list saved last time, with everyone present.
      list = (jsonDecode(cached) as List)
          .map((s) => {...Map<String, dynamic>.from(s as Map), 'status': null})
          .toList();
      _fromCache = true;
    }

    if (!mounted) return;
    setState(() {
      _students = List<Map<String, dynamic>>.from(
        list.map((e) => Map<String, dynamic>.from(e as Map)),
      );
      // Days filled in by an approved leave do not count as "already marked".
      _alreadyMarked = _students!.any(
        (s) => s['status'] != null && s['status'] != 'leave',
      );
      for (final s in _students!) {
        _status[s['id'] as int] = (s['status'] as String?) ?? 'present';
      }
      _error = null;
    });
  }

  void _toggle(int id) {
    final current = _status[id] ?? 'present';
    setState(() => _status[id] = current == 'present' ? 'absent' : 'present');
  }

  Future<void> _pick(int id) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            for (final status in [..._order, 'half_day'])
              ListTile(
                leading: Icon(Icons.circle, color: _colors[status]),
                title: Text(
                  _labels[status]!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, status),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _status[id] = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final queue = context.read<OfflineQueue>();
    try {
      final sent = await queue.sendOrQueue(
        '/teacher/sections/$_sectionId/attendance',
        {
          'date': _today,
          'records': [
            for (final e in _status.entries)
              {'student_id': e.key, 'status': e.value},
          ],
        },
      );
      if (!mounted) return;
      toast(
        context,
        sent ? 'Attendance saved. Parents have been informed.' : 'No internet: saved on this phone. It will be sent automatically.',
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Class ${widget.section['name']}';

    if (_error != null) {
      return AppPage(
        title: title,
        body: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: _error!,
          action: 'Retry',
          onAction: _load,
        ),
      );
    }
    if (_students == null) {
      return AppPage(
        title: title,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_students!.isEmpty) {
      return AppPage(
        title: title,
        body: const EmptyState(
          icon: Icons.groups_rounded,
          title: 'No students in this class',
        ),
      );
    }

    final absent = _status.values.where((s) => s == 'absent').length;
    final present = _status.values
        .where((s) => s == 'present' || s == 'late' || s == 'half_day')
        .length;

    return AppPage(
      title: title,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text('Save  -  $present present, $absent absent'),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Panel(
              color: (_fromCache ? AppColors.amber : Brand.current.primary)
                  .withValues(alpha: 0.1),
              borderColor: Colors.transparent,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _fromCache
                        ? Icons.cloud_off_rounded
                        : Icons.touch_app_rounded,
                    color: _fromCache
                        ? const Color(0xFF8A5A00)
                        : Brand.current.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fromCache
                          ? 'No internet. You can still take attendance - it is sent when internet is back.'
                          : (_alreadyMarked
                                ? 'Already marked today. You are editing.'
                                : 'Everyone is present. Tap a student who is absent. Long-press for late or leave.'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _students!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final student = _students![i];
                final id = student['id'] as int;
                final status = _status[id] ?? 'present';
                final color = _colors[status]!;
                return Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  color: status == 'present'
                      ? Colors.white
                      : color.withValues(alpha: 0.07),
                  borderColor: status == 'present'
                      ? null
                      : color.withValues(alpha: 0.5),
                  onTap: () => _toggle(id),
                  onLongPress: () => _pick(id),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${student['roll_no'] ?? '-'}',
                          style: const TextStyle(
                            color: AppColors.soft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Avatar(
                        name: student['name'] as String,
                        photoUrl: _fromCache
                            ? null
                            : student['photo_url'] as String?,
                        radius: 19,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          student['name'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _labels[status]!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
