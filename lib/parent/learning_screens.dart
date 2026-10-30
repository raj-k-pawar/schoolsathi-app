import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/files.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Downloads a protected attachment and opens it.
Future<void> openAttachment(BuildContext context, String url, String name) async {
  toast(context, 'Opening $name ...');
  final bytes = await guard(context, () => apiOf(context).download(url));
  if (bytes == null) return;
  final opened = await saveAndOpen(bytes, name);
  if (!opened && context.mounted) toast(context, 'No app on this phone can open this file.', error: true);
}

class HomeworkScreen extends StatelessWidget {
  const HomeworkScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Homework'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/children/${child['id']}/homework')) as Map<String, dynamic>)['homework'] as List<dynamic>,
        builder: (context, items, reload) {
          if (items.isEmpty) return EmptyState(icon: Icons.menu_book_rounded, title: tr('Nothing here yet'), subtitle: 'Homework posted by teachers appears here.');
          final today = DateUtils.dateOnly(DateTime.now());
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final hw = Map<String, dynamic>.from(items[i] as Map);
              final submission = hw['submission'] as Map?;
              final due = hw['due_date'] == null ? null : DateTime.tryParse(hw['due_date'] as String);
              final late = due != null && due.isBefore(today) && submission == null;
              return Panel(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HomeworkDetail(child: child, homework: hw)));
                  reload();
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconBadge(Icons.menu_book_rounded, color: Color(0xFF7A4DFF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hw['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          Text('${hw['subject'] ?? 'General'} - ${hw['teacher'] ?? ''}', style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (due != null) Pill('Due ${niceDate(hw['due_date'] as String, pattern: 'd MMM')}', color: late ? AppColors.red : AppColors.blue),
                            if (submission != null) Pill(submission['status'] == 'checked' ? 'Checked' : 'Submitted', color: AppColors.green, icon: Icons.check_rounded),
                            if ((hw['attachments'] as List).isNotEmpty) Pill('${(hw['attachments'] as List).length} file(s)', color: AppColors.soft, icon: Icons.attach_file_rounded),
                          ]),
                        ],
                      ),
                    ),
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

class HomeworkDetail extends StatefulWidget {
  const HomeworkDetail({super.key, required this.child, required this.homework});

  final Map<String, dynamic> child;
  final Map<String, dynamic> homework;

  @override
  State<HomeworkDetail> createState() => _HomeworkDetailState();
}

class _HomeworkDetailState extends State<HomeworkDetail> {
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  final _note = TextEditingController();
  bool _busy = false;
  late Map? _submission = widget.homework['submission'] as Map?;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1800);
        if (photo != null) setState(() => _photos.add(photo));
      } else {
        final photos = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1800);
        setState(() => _photos.addAll(photos));
      }
      if (_photos.length > 5) {
        setState(() => _photos.removeRange(5, _photos.length));
        if (mounted) toast(context, 'You can attach up to 5 photos.');
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open the camera or gallery. Please allow the permission.', error: true);
    }
  }

  Future<void> _submit() async {
    if (_photos.isEmpty) {
      toast(context, 'Add at least one photo of the homework.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final files = <UploadFile>[];
      for (final photo in _photos) {
        files.add(UploadFile('files[]', photo.name, await photo.readAsBytes()));
      }
      if (!mounted) return;
      await apiOf(context).upload('/children/${widget.child['id']}/homework/${widget.homework['id']}/submit', fields: {'note': _note.text.trim()}, files: files);
      if (!mounted) return;
      setState(() {
        _submission = {'status': 'submitted'};
        _photos.clear();
      });
      toast(context, 'Homework submitted.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hw = widget.homework;
    final attachments = hw['attachments'] as List;
    final checked = _submission?['status'] == 'checked';

    return AppPage(
      title: tr('Homework'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hw['title'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${hw['subject'] ?? 'General'} - ${hw['teacher'] ?? ''} - ${niceDate(hw['posted_at'] as String?)}', style: const TextStyle(color: AppColors.soft)),
                if (hw['due_date'] != null) Padding(padding: const EdgeInsets.only(top: 10), child: Pill('Due ${niceDate(hw['due_date'] as String)}', icon: Icons.event_rounded)),
                if ((hw['description'] as String?)?.isNotEmpty ?? false) ...[
                  const Divider(height: 28),
                  Text(hw['description'] as String, style: const TextStyle(height: 1.5, fontSize: 15)),
                ],
                for (final file in attachments)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton.icon(
                      onPressed: () => openAttachment(context, (file as Map)['url'] as String, file['name'] as String),
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(file['name'] as String, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_submission != null)
            Panel(
              color: AppColors.green.withValues(alpha: 0.08),
              borderColor: Colors.transparent,
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(checked ? 'Checked by the teacher' : 'Submitted', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if ((_submission!['teacher_remark'] as String?)?.isNotEmpty ?? false) Text('Remark: ${_submission!['teacher_remark']}'),
                    if (!checked) const Text('You can submit again to replace it.', style: TextStyle(color: AppColors.soft, fontSize: 13)),
                  ]),
                ),
              ]),
            ),
          if (!checked) ...[
            const SectionTitle('Submit your work'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (var i = 0; i < _photos.length; i++)
                          Chip(label: Text('Photo ${i + 1}'), avatar: const Icon(Icons.image_rounded, size: 18), onDeleted: () => setState(() => _photos.removeAt(i))),
                      ]),
                    ),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _add(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Camera'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _add(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: const Text('Gallery'))),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: _note, maxLength: 1000, decoration: const InputDecoration(labelText: 'Note for the teacher (optional)', counterText: '', fillColor: AppColors.bg)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : Text(tr('Submit'))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Notices'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/children/${child['id']}/notices')) as Map<String, dynamic>)['notices'] as List<dynamic>,
        builder: (context, notices, _) {
          if (notices.isEmpty) return EmptyState(icon: Icons.campaign_rounded, title: tr('Nothing here yet'), subtitle: 'Notices and circulars from the school appear here.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: notices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final notice = Map<String, dynamic>.from(notices[i] as Map);
              return Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const IconBadge(Icons.campaign_rounded, color: Color(0xFFFF5C7A), size: 38),
                      const SizedBox(width: 10),
                      Expanded(child: Text(notice['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    ]),
                    const SizedBox(height: 10),
                    Text(notice['body'] as String, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text(niceDate(notice['published_at'] as String?, pattern: 'd MMM yyyy, h:mm a'), style: const TextStyle(color: AppColors.soft, fontSize: 12)),
                      const Spacer(),
                      if (notice['attachment_url'] != null)
                        TextButton.icon(onPressed: () => openAttachment(context, notice['attachment_url'] as String, 'notice-${notice['id']}.pdf'), icon: const Icon(Icons.attach_file_rounded, size: 18), label: const Text('Attachment')),
                    ]),
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

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.child});

  final Map<String, dynamic> child;

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);

    return AppPage(
      title: tr('Results'),
      body: Loader<List<dynamic>>(
        load: () async => ((await api.get('/children/${child['id']}/results')) as Map<String, dynamic>)['exams'] as List<dynamic>,
        builder: (context, exams, _) {
          if (exams.isEmpty) return EmptyState(icon: Icons.emoji_events_rounded, title: tr('Nothing here yet'), subtitle: 'Results appear here when the school publishes them.');
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            itemCount: exams.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final exam = Map<String, dynamic>.from(exams[i] as Map);
              final passed = exam['result'] == 'Pass';
              final percent = exam['percent'] as num?;
              return Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(gradient: Brand.current.gradient, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(exam['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, children: [
                                Pill('${exam['result']}', color: Colors.white),
                                Pill('Grade ${exam['grade']}', color: Colors.white),
                                if (exam['rank'] != null) Pill('Rank ${exam['rank']}', color: Colors.white),
                              ]),
                            ]),
                          ),
                          Column(children: [
                            Text(percent == null ? '-' : '${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}%', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                            Text('${exam['total']} / ${exam['max']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                          ]),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      child: Column(
                        children: [
                          for (final s in exam['subjects'] as List)
                            Builder(builder: (context) {
                              final subject = Map<String, dynamic>.from(s as Map);
                              final marks = subject['marks'] as num?;
                              final max = (subject['max_marks'] as num).toDouble();
                              final failed = subject['absent'] == true || (marks != null && marks < (subject['pass_marks'] as num));
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                child: Column(children: [
                                  Row(children: [
                                    Expanded(child: Text(subject['subject'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
                                    Text(subject['absent'] == true ? 'Absent' : (marks == null ? '-' : '${marks.toStringAsFixed(marks % 1 == 0 ? 0 : 1)} / ${max.toStringAsFixed(0)}'), style: TextStyle(fontWeight: FontWeight.w800, color: failed ? AppColors.red : AppColors.ink)),
                                  ]),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(value: marks == null || max == 0 ? 0 : (marks / max).clamp(0, 1).toDouble(), minHeight: 7, backgroundColor: AppColors.bg, color: failed ? AppColors.red : AppColors.green),
                                  ),
                                ]),
                              );
                            }),
                          if ((exam['remark'] as String?)?.isNotEmpty ?? false) ...[
                            const Divider(height: 24),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.format_quote_rounded, color: passed ? AppColors.green : AppColors.amber),
                              const SizedBox(width: 8),
                              Expanded(child: Text(exam['remark'] as String, style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4))),
                            ]),
                          ],
                        ],
                      ),
                    ),
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

/// Weekly timetable. [path] is the API path, so the teacher app can reuse this screen.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key, this.child, this.path});

  final Map<String, dynamic>? child;
  final String? path;

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  // Monday = 0 ... Saturday = 5; Sunday shows Monday.
  int _day = (DateTime.now().weekday - 1).clamp(0, 5);

  @override
  Widget build(BuildContext context) {
    final api = apiOf(context);
    final path = widget.path ?? '/children/${widget.child!['id']}/timetable';

    return AppPage(
      title: tr('Timetable'),
      body: Loader<Map<String, dynamic>>(
        load: () async => (await api.get(path)) as Map<String, dynamic>,
        builder: (context, data, _) {
          final days = data['days'] as List;
          final cover = (data['substitutions_today'] as List?) ?? const [];
          if (days.every((d) => ((d as Map)['periods'] as List).isEmpty) && cover.isEmpty) {
            return EmptyState(icon: Icons.grid_view_rounded, title: tr('Nothing here yet'), subtitle: 'The school has not added the timetable yet.');
          }
          final periods = ((days[_day] as Map)['periods'] as List);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              if (cover.isNotEmpty) ...[
                Panel(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  borderColor: Colors.transparent,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('You are covering today', style: TextStyle(fontWeight: FontWeight.w800)),
                    for (final c in cover) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${(c as Map)['period']} (${c['start']}-${c['end']})  -  Class ${c['class']}  ${c['subject'] ?? ''}')),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: days.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final selected = i == _day;
                    return ChoiceChip(
                      label: Text(((days[i] as Map)['name'] as String).substring(0, 3)),
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _day = i),
                      selectedColor: Brand.current.primary,
                      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.ink, fontWeight: FontWeight.w700),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (periods.isEmpty) const Panel(child: Text('No classes on this day.', style: TextStyle(color: AppColors.soft))),
              for (final p in periods)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Builder(builder: (context) {
                    final period = Map<String, dynamic>.from(p as Map);
                    return Panel(
                      child: Row(children: [
                        Container(
                          width: 74,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: Brand.current.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                          child: Column(children: [
                            Text(niceTime(period['start'] as String?), style: TextStyle(fontWeight: FontWeight.w800, color: Brand.current.primary, fontSize: 13)),
                            Text(niceTime(period['end'] as String?), style: const TextStyle(color: AppColors.soft, fontSize: 11)),
                          ]),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((period['subject'] as String?) ?? 'Free period', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text(period['teacher'] != null ? '${period['teacher']}' : (period['class'] != null ? 'Class ${period['class']}' : '${period['period']}'), style: const TextStyle(color: AppColors.soft, fontSize: 13)),
                          ]),
                        ),
                        Text(period['period'] as String? ?? '', style: const TextStyle(color: AppColors.soft, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    );
                  }),
                ),
            ],
          );
        },
      ),
    );
  }
}
