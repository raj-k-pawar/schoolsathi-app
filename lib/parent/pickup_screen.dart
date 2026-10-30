import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Parent: how my child goes home, who may pick them up (with photos), one-day changes, early leave.
class PickupScreen extends StatefulWidget {
  const PickupScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  final _loader = GlobalKey<LoaderState<Map<String, dynamic>>>();

  String get _base => '/children/${widget.child['id']}/pickup';
  String get _first => (widget.child['name'] as String).split(' ').first;

  static const _icons = {'bus': Icons.directions_bus_rounded, 'parent': Icons.family_restroom_rounded, 'self': Icons.directions_walk_rounded};

  Future<void> _reload() async => _loader.currentState?.reload();

  Future<void> _run(Future<dynamic> Function() action) async {
    final result = await guard(context, action);
    if (result != null && mounted) {
      toast(context, (result as Map)['message'] as String? ?? 'Saved.');
      await _reload();
    }
  }

  Future<void> _setDay(String date, String? mode) => _run(() => apiOf(context).put('$_base/day', {'date': date, 'mode': mode}));

  Future<void> _saveUsual(Map<String, dynamic> data, {String? arrival, String? departure, bool? walkAlone}) async {
    if (walkAlone == true && data['walk_alone'] != true) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Let $_first go home alone?'),
          content: Text('The school gate will let $_first leave without an adult. You can change this any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I agree'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final walk = walkAlone ?? data['walk_alone'] == true;
    var leave = departure ?? data['departure_mode'] as String;
    if (!walk && leave == 'self') leave = 'parent';
    if (!mounted) return;
    await _run(() => apiOf(context).put(_base, {'arrival_mode': arrival ?? data['arrival_mode'], 'departure_mode': leave, 'walk_alone': walk}));
  }

  Future<void> _requestPass() async {
    final reason = TextEditingController();
    var date = DateTime.now();
    TimeOfDay? time;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Early leave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(DateFormat('EEE, d MMM').format(date)),
                onPressed: () async {
                  final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (picked != null) setLocal(() => date = picked);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule_rounded),
                label: Text(time == null ? 'Leaving time (optional)' : time!.format(context)),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 11, minute: 0));
                  if (picked != null) setLocal(() => time = picked);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                maxLength: 255,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. doctor appointment'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (reason.text.trim().isEmpty) {
      toast(context, 'Please write the reason.', error: true);
      return;
    }
    await _run(
      () => apiOf(context).post('/children/${widget.child['id']}/gate-passes', {
        'date': DateFormat('yyyy-MM-dd').format(date),
        if (time != null) 'leave_at': '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
        'reason': reason.text.trim(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tomorrow = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

    return AppPage(
      title: 'Pickup and travel',
      body: Loader<Map<String, dynamic>>(
        key: _loader,
        load: () async => Map<String, dynamic>.from(await api.get(_base) as Map),
        builder: (context, data, reload) {
          final modes = Map<String, String>.from(data['modes'] as Map);
          final hasBus = data['has_bus'] == true;
          final walkAlone = data['walk_alone'] == true;
          final plans = {for (final p in (data['plans'] as List)) (p as Map)['date'] as String: p['mode'] as String};
          final people = List<Map<String, dynamic>>.from((data['people'] as List).map((p) => Map<String, dynamic>.from(p as Map)));
          final passes = List<Map<String, dynamic>>.from((data['gate_passes'] as List).map((p) => Map<String, dynamic>.from(p as Map)));
          final choices = [if (hasBus) 'bus', 'parent', if (walkAlone) 'self'];

          Widget dayRow(String label, String date) {
            final planned = plans[date];
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(label: const Text('As usual'), selected: planned == null, onSelected: (_) => planned == null ? null : _setDay(date, null)),
                      for (final m in choices)
                        ChoiceChip(
                          avatar: Icon(_icons[m], size: 18),
                          label: Text(m == 'parent' ? 'I will pick up' : modes[m]!),
                          selected: planned == m,
                          onSelected: (_) => planned == m ? null : _setDay(date, m),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Panel(
                gradient: Brand.current.gradient,
                child: Row(
                  children: [
                    Icon(_icons[data['today_mode']] ?? Icons.home_rounded, color: Colors.white, size: 36),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Today $_first goes home: ${modes[data['today_mode']] ?? '-'}',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionTitle('Change for one day'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Picking up yourself, or someone else today? Tell the school here.', style: TextStyle(color: AppColors.soft)),
                    dayRow('Today', today),
                    dayRow('Tomorrow', tomorrow),
                  ],
                ),
              ),
              const SectionTitle('Usual way'),
              Panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Comes to school', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        DropdownButton<String>(
                          value: data['arrival_mode'] as String,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final m in modes.keys)
                              if (m != 'bus' || hasBus) DropdownMenuItem(value: m, child: Text(m == 'parent' ? 'Dropped by family' : modes[m]!)),
                          ],
                          onChanged: (v) => v == null ? null : _saveUsual(data, arrival: v),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Goes home', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        DropdownButton<String>(
                          value: data['departure_mode'] as String,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final m in modes.keys)
                              if ((m != 'bus' || hasBus) && (m != 'self' || walkAlone)) DropdownMenuItem(value: m, child: Text(modes[m]!)),
                          ],
                          onChanged: (v) => v == null ? null : _saveUsual(data, departure: v),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: walkAlone,
                      title: const Text('Allowed to go home alone', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Without this, the gate only hands your child to the people below.'),
                      onChanged: (v) => _saveUsual(data, walkAlone: v),
                    ),
                  ],
                ),
              ),
              SectionTitle(
                'Who may pick up $_first',
                action: 'Add',
                onAction: () async {
                  final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _AddPersonScreen(childId: widget.child['id'] as int)));
                  if (added == true) await _reload();
                },
              ),
              for (final p in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Row(
                      children: [
                        Avatar(name: p['name'] as String, photoUrl: p['photo_url'] as String?, radius: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text([p['relation'], p['phone']].whereType<String>().join('  ·  '), style: const TextStyle(color: AppColors.soft)),
                            ],
                          ),
                        ),
                        if (p['type'] == 'person')
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Remove ${p['name']}?'),
                                  content: const Text('They will no longer be able to pick up your child.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Remove', style: TextStyle(color: AppColors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true && context.mounted) await _run(() => api.delete('$_base/people/${p['id']}'));
                            },
                          )
                        else
                          const Pill('Parent', color: AppColors.green),
                      ],
                    ),
                  ),
                ),
              SectionTitle('Early leave', action: 'Request', onAction: _requestPass),
              if (passes.isEmpty)
                const Panel(
                  child: Text('Need to take your child early? Request it here; the office approves it and the gate is told.', style: TextStyle(color: AppColors.soft)),
                ),
              for (final g in passes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${niceDate(g['date'] as String, pattern: 'EEE, d MMM')}${g['leave_at'] != null ? ' at ${niceTime(g['leave_at'] as String)}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(g['reason'] as String, style: const TextStyle(color: AppColors.soft)),
                            ],
                          ),
                        ),
                        Pill(g['status_label'] as String, color: {'approved': AppColors.green, 'rejected': AppColors.red, 'pending': AppColors.amber}[g['status']] ?? AppColors.soft),
                        if (g['status'] == 'pending' || g['status'] == 'approved')
                          IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: () => _run(() => api.delete('/children/${widget.child['id']}/gate-passes/${g['id']}'))),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddPersonScreen extends StatefulWidget {
  const _AddPersonScreen({required this.childId});

  final int childId;

  @override
  State<_AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends State<_AddPersonScreen> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _phone = TextEditingController();
  XFile? _photo;
  bool _allChildren = true;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    try {
      final photo = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1000, preferredCameraDevice: CameraDevice.front);
      if (photo != null) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) toast(context, 'Could not open the camera or gallery. Please allow the permission.', error: true);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _relation.text.trim().isEmpty) {
      toast(context, 'Please enter the name and relation.', error: true);
      return;
    }
    setState(() => _busy = true);
    final result = await guard(
      context,
      () async => apiOf(context).upload(
        '/children/${widget.childId}/pickup/people',
        fields: {'name': _name.text.trim(), 'relation': _relation.text.trim(), if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(), 'all_children': _allChildren ? '1' : '0'},
        files: [if (_photo != null) UploadFile('photo', _photo!.name, await _photo!.readAsBytes())],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      toast(context, (result as Map)['message'] as String);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Add a pickup person',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('The gate shows this photo when someone comes for your child, so use a clear photo of the face.', style: TextStyle(color: AppColors.soft)),
          const SizedBox(height: 16),
          Center(
            child: _photo == null
                ? const CircleAvatar(radius: 56, child: Icon(Icons.person_rounded, size: 56))
                : ClipOval(
                    child: FutureBuilder(
                      future: _photo!.readAsBytes(),
                      builder: (context, snap) => snap.hasData ? Image.memory(snap.data!, width: 112, height: 112, fit: BoxFit.cover) : const SizedBox(width: 112, height: 112),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Take photo')),
              TextButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: const Text('Gallery')),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _relation,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Relation', hintText: 'Grandfather, aunt, driver ...'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(labelText: 'Mobile (optional)', counterText: ''),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _allChildren,
            onChanged: (v) => setState(() => _allChildren = v ?? true),
            title: const Text('For all my children in this school'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
