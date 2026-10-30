import 'package:flutter/material.dart';

import 'api.dart';
import 'scanner.dart';
import 'theme.dart';
import 'widgets.dart';

/// Safe dismissal at the gate (gate tablet and teacher app): scan the ID card, see how the child
/// goes home and who may collect them (with photos), hand the child over or stop a stranger.
class DismissalScanScreen extends StatefulWidget {
  const DismissalScanScreen({super.key});

  @override
  State<DismissalScanScreen> createState() => _DismissalScanScreenState();
}

class _DismissalScanScreenState extends State<DismissalScanScreen> {
  bool _busy = false;

  Future<void> _onCode(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final data = await guard(context, () => apiOf(context).post('/teacher/dismissal/lookup', {'code': code}));
    if (data != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DismissalCheckScreen(data: Map<String, dynamic>.from(data as Map))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Dismissal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: () => open(context, const StillInSchoolScreen()),
            icon: const Icon(Icons.groups_rounded, color: Colors.white),
            label: const Text('Still in school', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: QrScannerView(onCode: _onCode, paused: _busy),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            color: AppColors.ink,
            child: Row(
              children: [
                _busy
                    ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Scan the ID card of the child who is leaving',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One child at the gate: warnings, the people who may take them, and the actions.
class DismissalCheckScreen extends StatefulWidget {
  const DismissalCheckScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<DismissalCheckScreen> createState() => _DismissalCheckScreenState();
}

class _DismissalCheckScreenState extends State<DismissalCheckScreen> {
  bool _busy = false;

  Map<String, dynamic> get _student => Map<String, dynamic>.from(widget.data['student'] as Map);
  String get _firstName => (_student['name'] as String).split(' ').first;

  Future<bool> _confirm(String title, String body, {String ok = 'Yes', Color color = AppColors.green}) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _checkOut(Map<String, dynamic> body, String question) async {
    if (!await _confirm('Let $_firstName go?', question)) return;
    await _send(body);
  }

  Future<void> _send(Map<String, dynamic> body) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await apiOf(context).post('/teacher/dismissal/checkout', {'student_id': _student['id'], ...body}) as Map<String, dynamic>;
      if (!mounted) return;
      toast(context, result['message'] as String);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.fieldErrors.containsKey('early') && body['override'] != true) {
        // No early-leave pass: only with the office's word.
        final go = await _confirm('No early-leave pass', '${e.message}\n\nLet $_firstName go anyway because the office said so?', ok: 'Office approved', color: AppColors.amber);
        if (go) await _send({...body, 'override': true});
      } else {
        toast(context, e.message, error: true);
      }
    }
  }

  Future<void> _refuse() async {
    final name = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not on the pickup list'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Keep $_firstName at school. The parents and the office get an alert at once.'),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name of the person who came'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. says he is an uncle'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red, minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop and alert'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    final result = await guard(context, () => apiOf(context).post('/teacher/dismissal/refuse', {'student_id': _student['id'], 'person_name': name.text.trim(), 'note': note.text.trim()}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      toast(context, (result as Map)['message'] as String);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final warnings = List<String>.from(data['warnings'] as List? ?? const []);
    final people = List<Map<String, dynamic>>.from((data['people'] as List? ?? const []).map((p) => Map<String, dynamic>.from(p as Map)));
    final left = data['checked_out_at'] != null;
    final mode = data['mode'] as String? ?? 'parent';
    final modeColor = {'bus': AppColors.amber, 'self': AppColors.blue}[mode] ?? AppColors.green;

    return Scaffold(
      appBar: AppBar(title: const Text('Check out')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Panel(
              child: Row(
                children: [
                  Avatar(name: _student['name'] as String, photoUrl: _student['photo_url'] as String?, radius: 38),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_student['name'] as String, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                        Text('Class ${_student['class'] ?? '-'}', style: const TextStyle(color: AppColors.soft, fontSize: 15)),
                        const SizedBox(height: 6),
                        Pill(
                          'Goes home: ${data['mode_label']}',
                          color: modeColor,
                          icon: mode == 'bus' ? Icons.directions_bus_rounded : (mode == 'self' ? Icons.directions_walk_rounded : Icons.family_restroom_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: (left ? AppColors.red : AppColors.amber).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(left ? Icons.block_rounded : Icons.info_outline_rounded, color: left ? AppColors.red : const Color(0xFF8A5A00)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(fontWeight: FontWeight.w600, color: left ? AppColors.red : const Color(0xFF8A5A00)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!left) ...[
              const SectionTitle('Who came for the child?'),
              for (final p in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    onTap: () =>
                        _checkOut({'mode': 'parent', 'person_type': p['type'], 'person_id': p['id']}, 'Hand $_firstName to ${p['name']} (${p['relation'] ?? ''})? Check their face against the photo.'),
                    child: Row(
                      children: [
                        Avatar(name: p['name'] as String, photoUrl: p['photo_url'] as String?, radius: 34),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                              Text([p['relation'], p['phone']].whereType<String>().join('  ·  '), style: const TextStyle(color: AppColors.soft)),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle_outline_rounded, color: AppColors.green, size: 30),
                      ],
                    ),
                  ),
                ),
              if (data['may_go_alone'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
                    onPressed: () => _checkOut({'mode': 'self'}, 'The parents allowed $_firstName to go home alone.'),
                    icon: const Icon(Icons.directions_walk_rounded),
                    label: const Text('Goes home alone'),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _refuse,
                icon: const Icon(Icons.front_hand_rounded),
                label: const Text('Not on the list - stop'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Children who came today and have not left yet.
class StillInSchoolScreen extends StatelessWidget {
  const StillInSchoolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    return AppPage(
      title: 'Still in school',
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/teacher/dismissal/pending')) as Map<String, dynamic>)['students'] as List<dynamic>,
        builder: (context, students, reload) {
          if (students.isEmpty) {
            return const EmptyState(icon: Icons.verified_rounded, title: 'Everyone has left', subtitle: 'All children who came today have gone home.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: students.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Text('${students.length} children still in school', style: const TextStyle(color: AppColors.soft, fontWeight: FontWeight.w600));
              }
              final s = Map<String, dynamic>.from(students[i - 1] as Map);
              return Panel(
                onTap: () async {
                  final data = await guard(context, () => api.post('/teacher/dismissal/lookup', {'student_id': s['id']}));
                  if (data != null && context.mounted) {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DismissalCheckScreen(data: Map<String, dynamic>.from(data as Map))));
                    await reload();
                  }
                },
                child: Row(
                  children: [
                    Avatar(name: s['name'] as String, photoUrl: s['photo_url'] as String?),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text('Class ${s['class'] ?? '-'}', style: const TextStyle(color: AppColors.soft)),
                        ],
                      ),
                    ),
                    Pill(s['mode_label'] as String, color: {'bus': AppColors.amber, 'self': AppColors.blue}[s['mode']] ?? AppColors.green),
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
