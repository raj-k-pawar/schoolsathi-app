import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  static const _colors = {
    'present': AppColors.green,
    'late': AppColors.amber,
    'half_day': AppColors.amber,
    'absent': AppColors.red,
    'leave': AppColors.blue,
  };

  void _move(int by) {
    final next = DateTime(_month.year, _month.month + by);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final key = DateFormat('yyyy-MM').format(_month);

    return AppPage(
      title: tr('Attendance'),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(key),
        load: () async => (await api.get('/children/${widget.child['id']}/attendance', query: {'month': key})) as Map<String, dynamic>,
        builder: (context, data, _) {
          final days = {for (final d in data['days'] as List) (d as Map)['date'] as String: d['status'] as String};
          final percent = data['year_percent'] as num?;
          final counts = <String, int>{};
          for (final status in days.values) {
            counts[status] = (counts[status] ?? 0) + 1;
          }

          final first = DateTime(_month.year, _month.month, 1);
          final total = DateUtils.getDaysInMonth(_month.year, _month.month);
          final cells = <DateTime?>[...List.filled(first.weekday - 1, null), for (var d = 1; d <= total; d++) DateTime(_month.year, _month.month, d)];
          final today = DateUtils.dateOnly(DateTime.now());

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Panel(
                gradient: Brand.current.gradient,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(value: (percent ?? 0) / 100, strokeWidth: 8, backgroundColor: Colors.white.withValues(alpha: 0.25), color: Colors.white, strokeCap: StrokeCap.round),
                          Center(child: Text(percent == null ? '-' : '${percent.round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Attendance this year'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                          Text(widget.child['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                          if (percent != null && percent < 75)
                            const Padding(padding: EdgeInsets.only(top: 6), child: Pill('Below 75% - please attend regularly', color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left_rounded)),
                        Expanded(child: Text(DateFormat('MMMM yyyy').format(_month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                        IconButton(onPressed: DateTime(_month.year, _month.month + 1).isAfter(DateTime.now()) ? null : () => _move(1), icon: const Icon(Icons.chevron_right_rounded)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w700, fontSize: 12))))]),
                    const SizedBox(height: 6),
                    GridView.count(
                      crossAxisCount: 7,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      children: [
                        for (final day in cells)
                          if (day == null)
                            const SizedBox.shrink()
                          else
                            Builder(builder: (context) {
                              final status = days[DateFormat('yyyy-MM-dd').format(day)];
                              final color = _colors[status];
                              final isToday = day == today;
                              return Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color?.withValues(alpha: 0.16) ?? (day.weekday == 7 ? AppColors.bg : null),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isToday ? Border.all(color: AppColors.ink, width: 1.6) : null,
                                ),
                                child: Text('${day.day}', style: TextStyle(fontWeight: FontWeight.w700, color: color ?? (day.isAfter(today) ? AppColors.line : AppColors.soft))),
                              );
                            }),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (label, key, color) in [(tr('Present'), 'present', AppColors.green), (tr('Absent'), 'absent', AppColors.red), (tr('Late'), 'late', AppColors.amber), (tr('Leave'), 'leave', AppColors.blue)]) ...[
                    Expanded(
                      child: Panel(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                        child: Column(children: [
                          Text('${(counts[key] ?? 0) + (key == 'late' ? (counts['half_day'] ?? 0) : 0)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.soft, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                    if (key != 'leave') const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
