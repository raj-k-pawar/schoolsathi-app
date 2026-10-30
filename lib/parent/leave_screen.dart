import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final _loader = GlobalKey<LoaderState<List<dynamic>>>();

  Future<void> _apply() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _LeaveForm(childId: widget.child['id'] as int),
    );
    if (sent == true) {
      _loader.currentState?.reload();
      if (mounted) toast(context, 'Leave request sent to the class teacher.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Leave'),
      fab: FloatingActionButton.extended(onPressed: _apply, icon: const Icon(Icons.add_rounded), label: Text(tr('Apply for leave'))),
      body: Loader<List<dynamic>>(
        key: _loader,
        load: () async => ((await api.get('/children/${widget.child['id']}/leave')) as Map<String, dynamic>)['leaves'] as List<dynamic>,
        builder: (context, leaves, _) {
          if (leaves.isEmpty) {
            return EmptyState(icon: Icons.event_available_rounded, title: tr('Nothing here yet'), subtitle: 'Tap "Apply for leave" when your child will be away from school.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: leaves.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final leave = Map<String, dynamic>.from(leaves[i] as Map);
              final (label, color) = switch (leave['status']) {
                'approved' => ('Approved', AppColors.green),
                'rejected' => ('Not approved', AppColors.red),
                _ => ('Waiting for teacher', AppColors.amber),
              };
              final same = leave['from_date'] == leave['to_date'];
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(same ? niceDate(leave['from_date'] as String) : '${niceDate(leave['from_date'] as String, pattern: 'd MMM')} - ${niceDate(leave['to_date'] as String)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                      Pill(label, color: color),
                    ]),
                    const SizedBox(height: 6),
                    Text(leave['reason'] as String, style: const TextStyle(color: AppColors.soft, height: 1.35)),
                    if ((leave['remark'] as String?)?.isNotEmpty ?? false)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Teacher: ${leave['remark']}', style: const TextStyle(fontWeight: FontWeight.w600))),
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

class _LeaveForm extends StatefulWidget {
  const _LeaveForm({required this.childId});

  final int childId;

  @override
  State<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<_LeaveForm> {
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  DateTime _to = DateUtils.dateOnly(DateTime.now());
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isFrom) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(context: context, initialDate: isFrom ? _from : _to, firstDate: isFrom ? today : _from, lastDate: today.add(const Duration(days: 80)));
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 3) {
      toast(context, 'Please write the reason for leave.', error: true);
      return;
    }
    setState(() => _busy = true);
    final format = DateFormat('yyyy-MM-dd');
    final ok = await guard(context, () => apiOf(context).post('/children/${widget.childId}/leave', {'from_date': format.format(_from), 'to_date': format.format(_to), 'reason': _reason.text.trim()}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    Widget dateBox(String label, DateTime date, bool isFrom) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _pick(isFrom),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppColors.soft, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(DateFormat('EEE, d MMM').format(date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Apply for leave'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(children: [dateBox(tr('From'), _from, true), const SizedBox(width: 10), dateBox(tr('To'), _to, false)]),
          const SizedBox(height: 12),
          TextField(controller: _reason, maxLines: 3, maxLength: 500, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('Reason'), alignLabelWithHint: true, fillColor: AppColors.bg)),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(tr('Submit'))),
        ],
      ),
    );
  }
}
